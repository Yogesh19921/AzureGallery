import Foundation
import Photos
import UIKit
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Uses Apple Foundation Models (iOS 26+) to enhance photo search.
///
/// Since the on-device model is text-only (no image input), we use it to:
/// 1. Generate richer captions from Vision metadata (labels + faces + text → natural sentence)
/// 2. Understand natural language search queries and match them against metadata
///
/// Falls back gracefully on older devices — the caption is built from raw Vision labels.
@Observable
@MainActor
final class CaptionService {
    static let shared = CaptionService()

    private(set) var isRunning = false
    private(set) var progress = 0
    private(set) var total = 0

    /// Whether Apple Foundation Models are available on this device.
    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    private let db = DatabaseService.shared

    private init() {}

    // MARK: - Caption from Vision metadata

    /// Generate a natural language caption from existing Vision analysis data.
    /// Uses Apple FM on iOS 26+ for richer descriptions, plain concatenation as fallback.
    nonisolated func captionFromMetadata(record: BackupRecord) async -> String? {
        let parts = buildMetadataDescription(record)
        guard !parts.isEmpty else { return nil }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return await enrichWithLLM(metadata: parts)
        }
        #endif

        // Fallback: join Vision labels into a simple caption
        return parts
    }

    // MARK: - Batch captioning

    /// Caption all photos that don't have a caption yet, using Vision metadata + LLM.
    func captionAll() async {
        guard !isRunning else { return }
        isRunning = true
        progress = 0

        while true {
            let batch = (try? db.assetIdsWithoutCaption(limit: 30)) ?? []
            if batch.isEmpty { break }
            total = max(total, progress + batch.count)

            for assetId in batch {
                guard isRunning else { break }
                guard let record = try? db.record(for: assetId) else { progress += 1; continue }

                if let caption = await captionFromMetadata(record: record) {
                    try? db.updateCaption(assetId: assetId, caption: caption)
                }
                progress += 1
            }
        }

        isRunning = false
        AppLogger.shared.info("Captioning complete: \(progress) photos", tag: "CaptionService")
    }

    func cancel() { isRunning = false }

    // MARK: - Private

    /// Build a text description from Vision metadata fields.
    nonisolated private func buildMetadataDescription(_ record: BackupRecord) -> String {
        var parts: [String] = []

        // Scene labels
        let labels = record.sceneLabelsArray
        if !labels.isEmpty {
            parts.append("scene: " + labels.joined(separator: ", "))
        }

        // Animals
        if let animalsJSON = record.animalLabels,
           let data = animalsJSON.data(using: .utf8),
           let animals = try? JSONDecoder().decode([String].self, from: data),
           !animals.isEmpty {
            parts.append("animals: " + animals.joined(separator: ", "))
        }

        // Faces
        if let fc = record.faceCount, fc > 0 {
            parts.append(fc == 1 ? "1 person" : "\(fc) people")
        }

        // Text content
        if record.hasText, let text = record.recognizedText, !text.isEmpty {
            let preview = String(text.prefix(100))
            parts.append("text in photo: \"\(preview)\"")
        }

        // Media type
        parts.append("type: " + record.mediaType)

        return parts.joined(separator: ". ")
    }

    /// Use Apple Foundation Models to turn raw metadata into a natural sentence.
    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    nonisolated private func enrichWithLLM(metadata: String) async -> String? {
        do {
            let session = LanguageModelSession(instructions: """
                You describe photos based on metadata. Write ONE concise sentence describing what the photo likely shows. \
                Be specific but don't invent details not supported by the metadata. \
                Output ONLY the description, nothing else.
                """)
            let response = try await session.respond(to: "Photo metadata: \(metadata)")
            let text = String(response.content).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? metadata : text
        } catch {
            // LLM unavailable or failed — fall back to raw metadata
            return metadata
        }
    }
    #endif
}
