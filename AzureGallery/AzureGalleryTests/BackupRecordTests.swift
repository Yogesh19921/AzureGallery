import XCTest
@testable import AzureGallery

final class BackupRecordTests: XCTestCase {

    // MARK: - Default init values

    func testDefaultStatusIsPending() {
        let r = BackupRecord(assetId: "a", blobName: "b.HEIC", mediaType: "image")
        XCTAssertEqual(r.status, .pending)
    }

    func testDefaultRetriesIsZero() {
        let r = BackupRecord(assetId: "a", blobName: "b.HEIC", mediaType: "image")
        XCTAssertEqual(r.retries, 0)
    }

    func testDefaultHasTextIsFalse() {
        let r = BackupRecord(assetId: "a", blobName: "b.HEIC", mediaType: "image")
        XCTAssertFalse(r.hasText)
    }

    func testDefaultFaceCountIsNil() {
        let r = BackupRecord(assetId: "a", blobName: "b.HEIC", mediaType: "image")
        XCTAssertNil(r.faceCount)
    }

    func testDefaultSceneLabelsIsNil() {
        let r = BackupRecord(assetId: "a", blobName: "b.HEIC", mediaType: "image")
        XCTAssertNil(r.sceneLabels)
    }

    func testCreatedAtIsValidISO8601() {
        let before = Date()
        let r = BackupRecord(assetId: "a", blobName: "b.HEIC", mediaType: "image")
        let after = Date()
        let parsed = ISO8601DateFormatter().date(from: r.createdAt)
        XCTAssertNotNil(parsed, "createdAt must be ISO8601")
        if let parsed {
            XCTAssertTrue(parsed >= before.addingTimeInterval(-1) && parsed <= after.addingTimeInterval(1))
        }
    }

    func testIdIsNilBeforeInsert() {
        let r = BackupRecord(assetId: "a", blobName: "b.HEIC", mediaType: "image")
        XCTAssertNil(r.id)
    }

    // MARK: - BackupStatus raw values

    func testStatusRawValues() {
        XCTAssertEqual(BackupStatus.pending.rawValue,   "pending")
        XCTAssertEqual(BackupStatus.uploading.rawValue, "uploading")
        XCTAssertEqual(BackupStatus.uploaded.rawValue,  "uploaded")
        XCTAssertEqual(BackupStatus.failed.rawValue,    "failed")
        XCTAssertEqual(BackupStatus.permFailed.rawValue,"perm_failed")
    }

    func testStatusInitFromRawValue() {
        XCTAssertEqual(BackupStatus(rawValue: "perm_failed"), .permFailed)
        XCTAssertEqual(BackupStatus(rawValue: "pending"),     .pending)
        XCTAssertNil(BackupStatus(rawValue: "bogus"))
    }

    // MARK: - sceneLabelsArray

    func testSceneLabelsArrayWhenNil() {
        var r = BackupRecord(assetId: "a", blobName: "b", mediaType: "image")
        r.sceneLabels = nil
        XCTAssertEqual(r.sceneLabelsArray, [])
    }

    func testSceneLabelsArrayDecodesJSON() throws {
        var r = BackupRecord(assetId: "a", blobName: "b", mediaType: "image")
        r.sceneLabels = try encode(["outdoor", "nature", "sky"])
        XCTAssertEqual(r.sceneLabelsArray, ["outdoor", "nature", "sky"])
    }

    func testSceneLabelsArrayEmptyArrayJSON() {
        var r = BackupRecord(assetId: "a", blobName: "b", mediaType: "image")
        r.sceneLabels = "[]"
        XCTAssertEqual(r.sceneLabelsArray, [])
    }

    func testSceneLabelsArrayMalformedJSONReturnsEmpty() {
        var r = BackupRecord(assetId: "a", blobName: "b", mediaType: "image")
        r.sceneLabels = "not-json"
        XCTAssertEqual(r.sceneLabelsArray, [])
    }

    // MARK: - GRDB round-trip (via DatabaseService)

    func testGRDBInsertAssignsId() throws {
        let db = try DatabaseService.makeInMemory()
        var r = BackupRecord(assetId: "asset-1", blobName: "test.HEIC", mediaType: "image")
        try db.upsert(&r)
        XCTAssertNotNil(r.id)
    }

    func testGRDBRoundTripPreservesAllFields() throws {
        let db = try DatabaseService.makeInMemory()
        var r = BackupRecord(assetId: "asset-1", blobName: "orig/2024/01/abc.HEIC", mediaType: "image",
                             creationDate: "2024-01-15T10:00:00Z")
        r.faceCount = 2
        r.hasText = true
        r.sceneLabels = try encode(["sky", "outdoor"])
        try db.upsert(&r)

        let fetched = try XCTUnwrap(try db.record(for: "asset-1"))
        XCTAssertEqual(fetched.blobName, "orig/2024/01/abc.HEIC")
        XCTAssertEqual(fetched.mediaType, "image")
        XCTAssertEqual(fetched.creationDate, "2024-01-15T10:00:00Z")
        XCTAssertEqual(fetched.faceCount, 2)
        XCTAssertTrue(fetched.hasText)
        XCTAssertEqual(fetched.sceneLabelsArray, ["sky", "outdoor"])
    }

    // MARK: - Helpers

    private func encode(_ value: [String]) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8)!
    }
}
