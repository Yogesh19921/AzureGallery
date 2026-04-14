import XCTest
@testable import AzureGallery

final class EmbeddingServiceTests: XCTestCase {

    // MARK: - Cosine Similarity

    func testCosineSimilarityIdenticalVectors() {
        let a: [Float] = [1, 2, 3, 4]
        let b: [Float] = [1, 2, 3, 4]
        let score = cosineSim(a, b)
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testCosineSimilarityOrthogonalVectors() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        let score = cosineSim(a, b)
        XCTAssertEqual(score, 0.0, accuracy: 0.001)
    }

    func testCosineSimilarityOppositeVectors() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [-1, -2, -3]
        let score = cosineSim(a, b)
        XCTAssertEqual(score, -1.0, accuracy: 0.001)
    }

    func testCosineSimilarityScaledVectorsEqual() {
        let a: [Float] = [1, 2, 3]
        let b: [Float] = [2, 4, 6]  // same direction, different magnitude
        let score = cosineSim(a, b)
        XCTAssertEqual(score, 1.0, accuracy: 0.001, "Cosine similarity should be scale-invariant")
    }

    func testCosineSimilarityEmptyVectors() {
        let score = cosineSim([], [])
        XCTAssertEqual(score, 0.0)
    }

    func testCosineSimilarityMismatchedLengths() {
        let score = cosineSim([1, 2], [1, 2, 3])
        XCTAssertEqual(score, 0.0, "Mismatched vectors should return 0")
    }

    // MARK: - Data Conversion

    func testFloatToDataRoundTrip() {
        let original: [Float] = [0.1, 0.5, -0.3, 1.0, 0.0]
        let data = floatsToData(original)
        XCTAssertEqual(data.count, original.count * MemoryLayout<Float>.size)
        let recovered = dataToFloats(data)
        XCTAssertEqual(recovered.count, original.count)
        for i in 0..<original.count {
            XCTAssertEqual(recovered[i], original[i], accuracy: 1e-6)
        }
    }

    func testEmptyDataToFloats() {
        let result = dataToFloats(Data())
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - DB Integration

    func testEmbeddingColumnRoundTrip() throws {
        let db = try DatabaseService.makeInMemory()
        var record = BackupRecord(assetId: "emb1", blobName: "emb1.HEIC", mediaType: "image")
        try db.upsert(&record)

        let embedding: [Float] = (0..<128).map { Float($0) / 128.0 }
        let data = floatsToData(embedding)
        try db.updateEmbedding(assetId: "emb1", embedding: data)

        let fetched = try XCTUnwrap(try db.record(for: "emb1"))
        XCTAssertNotNil(fetched.embedding)
        XCTAssertEqual(fetched.embedding?.count, 128 * MemoryLayout<Float>.size)
    }

    func testAssetIdsWithoutEmbedding() throws {
        let db = try DatabaseService.makeInMemory()
        var r1 = BackupRecord(assetId: "a1", blobName: "a1.HEIC", mediaType: "image")
        var r2 = BackupRecord(assetId: "a2", blobName: "a2.HEIC", mediaType: "image")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.updateEmbedding(assetId: "a1", embedding: floatsToData([1.0, 2.0]))

        let missing = try db.assetIdsWithoutEmbedding(limit: 10)
        XCTAssertEqual(missing, ["a2"])
    }

    func testAllEmbeddingsExcludesNulls() throws {
        let db = try DatabaseService.makeInMemory()
        var r1 = BackupRecord(assetId: "a1", blobName: "a1.HEIC", mediaType: "image")
        var r2 = BackupRecord(assetId: "a2", blobName: "a2.HEIC", mediaType: "image")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.updateEmbedding(assetId: "a1", embedding: floatsToData([1.0]))

        let all = try db.allEmbeddings()
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].assetId, "a1")
    }

    // MARK: - Helpers

    private func cosineSim(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, normA: Float = 0, normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]; normA += a[i] * a[i]; normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dot / denom : 0
    }

    private func floatsToData(_ floats: [Float]) -> Data {
        var f = floats
        return Data(bytes: &f, count: f.count * MemoryLayout<Float>.size)
    }

    private func dataToFloats(_ data: Data) -> [Float] {
        data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
