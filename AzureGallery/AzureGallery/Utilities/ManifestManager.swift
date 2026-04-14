import Foundation
import Photos

/// Metadata record for a single uploaded blob, stored in `metadata/manifest.json`.
struct ManifestEntry: Codable {
    let blobName: String
    let originalFilename: String?
    let creationDate: String?
    let mediaType: String
    let pixelWidth: Int
    let pixelHeight: Int
    let fileSize: Int64?
    let faceCount: Int?
    let sceneLabels: [String]?
    let recognizedText: [String]?
    let animalLabels: [String]?
}

/// Top-level manifest uploaded to `metadata/manifest.json` in the container.
struct Manifest: Codable {
    let version: Int
    var updated: String
    var assets: [String: ManifestEntry]  // key = blobName
}

/// Accumulates per-blob metadata and periodically uploads a JSON manifest to Azure.
///
/// The manifest (`metadata/manifest.json`) is a convenience index — the app does not
/// read it for normal operation. It is intended for external tools and restore workflows.
/// Uploads are fire-and-forget; manifest failures do not affect backup correctness.
final class ManifestManager {
    static let shared = ManifestManager()

    private let blobPath = "metadata/manifest.json"
    private var entries: [String: ManifestEntry] = [:]
    private var pendingFlush = 0
    /// Flush threshold: upload manifest to Azure every N new entries.
    private let flushThreshold = 50

    private init() {}

    /// Record a newly uploaded blob in the in-memory manifest.
    /// Triggers a flush to Azure once `flushThreshold` entries have accumulated.
    func addEntry(
        blobName: String,
        asset: PHAsset,
        analysis: VisionAnalysis,
        fileSize: Int64?
    ) {
        let formatter = ISO8601DateFormatter()
        let entry = ManifestEntry(
            blobName: blobName,
            originalFilename: nil,   // PHAsset doesn't expose original filename directly
            creationDate: asset.creationDate.map { formatter.string(from: $0) },
            mediaType: asset.mediaType == .video ? "video" : "image",
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            fileSize: fileSize,
            faceCount: analysis.faceCount > 0 ? analysis.faceCount : nil,
            sceneLabels: analysis.sceneLabels.isEmpty ? nil : analysis.sceneLabels.map(\.label),
            recognizedText: analysis.recognizedText.isEmpty ? nil : analysis.recognizedText,
            animalLabels: analysis.animalLabels.isEmpty ? nil : analysis.animalLabels
        )
        entries[blobName] = entry
        pendingFlush += 1
        if pendingFlush >= flushThreshold {
            Task { await flush(config: loadConfig()) }
        }
    }

    /// Upload the current manifest snapshot to Azure. No-op if `config` is nil or entries are empty.
    func flush(config: AzureConfig?) async {
        guard let config, !entries.isEmpty else { return }
        pendingFlush = 0
        let manifest = Manifest(
            version: 1,
            updated: ISO8601DateFormatter().string(from: Date()),
            assets: entries
        )
        guard let data = try? JSONEncoder().encode(manifest) else { return }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("manifest.json")
        try? data.write(to: tmpURL)
        let service = AzureBlobService(config: config)
        if let request = try? service.uploadRequest(
            blobName: blobPath,
            contentType: "application/json",
            fileSize: Int64(data.count)
        ) {
            // Fire-and-forget upload — non-critical
            URLSession.shared.uploadTask(with: request, fromFile: tmpURL).resume()
        }
    }

    private func loadConfig() -> AzureConfig? {
        guard let cs = KeychainHelper.load(key: KeychainHelper.connectionStringKey),
              let container = KeychainHelper.load(key: KeychainHelper.containerNameKey) else { return nil }
        return try? AzureConfig.parse(connectionString: cs, containerName: container)
    }
}
