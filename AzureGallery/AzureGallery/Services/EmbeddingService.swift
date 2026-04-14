import Foundation
import Vision
import CoreGraphics
import Photos
import UIKit
import Observation

/// Computes image embeddings using Apple's VNGenerateImageFeaturePrintRequest.
///
/// This provides image-to-image similarity search out of the box (no model download).
/// For text-to-image search, we bridge via Vision scene labels + NLEmbedding:
///   1. Compute a "text profile" — the average embedding of photos matching keyword-expanded labels
///   2. Find photos nearest to that profile
///
/// ## Future: Core ML CLIP
/// To upgrade to true text-to-image CLIP search, add a `.mlmodel` and swap the
/// `embedText()` implementation. The DB schema (512-float BLOB) is compatible.
@Observable
@MainActor
final class EmbeddingService {
    static let shared = EmbeddingService()

    private(set) var isIndexing = false
    private(set) var indexProgress = 0
    private(set) var indexTotal = 0

    private let db = DatabaseService.shared

    private init() {}

    // MARK: - Image Embedding (Apple Vision FeaturePrint)

    /// Generate a 2048-byte embedding for a CGImage using VNGenerateImageFeaturePrintRequest.
    /// Returns nil if Vision analysis fails.
    nonisolated func embedImage(_ cgImage: CGImage) -> Data? {
        let request = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard let result = request.results?.first else { return nil }
        // VNFeaturePrintObservation stores data internally — extract via computation
        // The feature print is a fixed-size float vector. We serialize it to Data.
        return featurePrintToData(result)
    }

    /// Extract raw bytes from a VNFeaturePrintObservation.
    nonisolated private func featurePrintToData(_ fp: VNFeaturePrintObservation) -> Data {
        let count = fp.elementCount
        var floats = [Float](repeating: 0, count: count)
        // Copy the feature print data — VNFeaturePrintObservation has a `data` property
        // that contains the raw float buffer.
        let data = fp.data
        data.withUnsafeBytes { buffer in
            guard let ptr = buffer.bindMemory(to: Float.self).baseAddress else { return }
            for i in 0..<count {
                floats[i] = ptr[i]
            }
        }
        return Data(bytes: &floats, count: count * MemoryLayout<Float>.size)
    }

    // MARK: - Similarity Search

    /// Find the top N most similar photos to the given embedding.
    nonisolated func search(queryEmbedding: Data, limit: Int = 50) -> [(assetId: String, score: Float)] {
        guard let allEmbeddings = try? db.allEmbeddings() else { return [] }
        let queryFloats = dataToFloats(queryEmbedding)
        guard !queryFloats.isEmpty else { return [] }

        var results: [(String, Float)] = []
        for (assetId, embData) in allEmbeddings {
            let floats = dataToFloats(embData)
            guard floats.count == queryFloats.count else { continue }
            let score = cosineSimilarity(queryFloats, floats)
            results.append((assetId, score))
        }

        return results
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { ($0.0, $0.1) }
    }

    /// Text-to-image search: expand the query into Vision labels via NLEmbedding,
    /// find photos matching those labels, compute the average embedding of matches,
    /// then find all photos nearest to that average.
    nonisolated func searchByText(_ query: String, limit: Int = 50) -> [(assetId: String, score: Float)] {
        // Step 1: Find seed photos via keyword search (existing approach)
        let expanded = SemanticSearchService.expandQuery(query, topN: 8)
        var seedIds = Set<String>()
        for kw in expanded {
            let matches = (try? db.searchRecords(sceneKeyword: kw, limit: 20)) ?? []
            for m in matches { seedIds.insert(m.assetId) }
        }
        // Also try direct query
        let direct = (try? db.searchRecords(sceneKeyword: query, limit: 20)) ?? []
        for d in direct { seedIds.insert(d.assetId) }
        let textMatches = (try? db.searchRecords(textQuery: query, limit: 20)) ?? []
        for t in textMatches { seedIds.insert(t.assetId) }

        // Step 2: Compute average embedding of seed photos
        guard let allEmbeddings = try? db.allEmbeddings() else { return [] }
        let seedEmbeddings = allEmbeddings.filter { seedIds.contains($0.assetId) }

        if seedEmbeddings.isEmpty {
            // No keyword matches — fall back to returning empty
            return []
        }

        let dim = dataToFloats(seedEmbeddings[0].embedding).count
        guard dim > 0 else { return [] }
        var avg = [Float](repeating: 0, count: dim)
        var count = 0
        for (_, data) in seedEmbeddings {
            let floats = dataToFloats(data)
            guard floats.count == dim else { continue }
            for i in 0..<dim { avg[i] += floats[i] }
            count += 1
        }
        guard count > 0 else { return [] }
        for i in 0..<dim { avg[i] /= Float(count) }
        let avgData = Data(bytes: &avg, count: dim * MemoryLayout<Float>.size)

        // Step 3: Find nearest photos to the average embedding
        return search(queryEmbedding: avgData, limit: limit)
    }

    /// Find photos similar to a given photo.
    nonisolated func findSimilar(assetId: String, limit: Int = 20) -> [(assetId: String, score: Float)] {
        guard let record = try? db.record(for: assetId),
              let embedding = record.embedding else { return [] }
        return search(queryEmbedding: embedding, limit: limit + 1)
            .filter { $0.assetId != assetId } // exclude self
    }

    // MARK: - Batch Indexing

    /// Index all photos that don't have embeddings yet. Call on charger for initial backfill.
    func indexAll() async {
        guard !isIndexing else { return }
        isIndexing = true
        indexProgress = 0

        while true {
            let batch = (try? db.assetIdsWithoutEmbedding(limit: 30)) ?? []
            if batch.isEmpty { break }
            indexTotal = max(indexTotal, indexProgress + batch.count)

            for assetId in batch {
                guard isIndexing else { break } // allow cancellation
                let assets = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
                guard let asset = assets.firstObject else {
                    indexProgress += 1
                    continue
                }
                // Load a small image for embedding
                let cgImage = await loadCGImage(for: asset)
                if let cg = cgImage {
                    let embData = await Task.detached(priority: .utility) {
                        self.embedImage(cg)
                    }.value
                    if let embData {
                        try? db.updateEmbedding(assetId: assetId, embedding: embData)
                    }
                }
                indexProgress += 1
            }
        }

        isIndexing = false
        AppLogger.shared.info("Embedding index complete: \(indexProgress) photos", tag: "EmbeddingService")
    }

    func cancelIndexing() {
        isIndexing = false
    }

    // MARK: - Helpers

    nonisolated private func dataToFloats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
    }

    nonisolated private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    private func loadCGImage(for asset: PHAsset) async -> CGImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isNetworkAccessAllowed = false
            options.isSynchronous = false
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 384, height: 384),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}
