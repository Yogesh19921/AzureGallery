import XCTest
@preconcurrency import GRDB
@testable import AzureGallery

/// Tests the full DatabaseService API against an in-memory SQLite database.
/// Each test gets a fresh database via makeInMemory(), so there is no shared state.
final class DatabaseServiceTests: XCTestCase {

    var db: DatabaseService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        db = try DatabaseService.makeInMemory()
    }

    // MARK: - Upsert & fetch

    func testUpsertAssignsId() throws {
        var r = makeRecord("a1")
        try db.upsert(&r)
        XCTAssertNotNil(r.id)
    }

    func testFetchByAssetId() throws {
        var r = makeRecord("a1")
        try db.upsert(&r)
        let fetched = try XCTUnwrap(try db.record(for: "a1"))
        XCTAssertEqual(fetched.assetId,  "a1")
        XCTAssertEqual(fetched.blobName, "a1.HEIC")
        XCTAssertEqual(fetched.status,   .pending)
        XCTAssertEqual(fetched.retries,  0)
    }

    func testFetchMissingAssetReturnsNil() throws {
        XCTAssertNil(try db.record(for: "nonexistent"))
    }

    func testUpsertUpdatesExistingRecord() throws {
        var r = makeRecord("a1")
        try db.upsert(&r)
        r.blobName = "updated.HEIC"
        try db.upsert(&r)
        let fetched = try XCTUnwrap(try db.record(for: "a1"))
        XCTAssertEqual(fetched.blobName, "updated.HEIC")
    }

    func testAllAssetIds() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        try db.upsert(&r1); try db.upsert(&r2)
        XCTAssertEqual(try db.allAssetIds(), ["a1", "a2"])
    }

    func testAllRecordsCount() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        try db.upsert(&r1); try db.upsert(&r2)
        XCTAssertEqual(try db.allRecords().count, 2)
    }

    // MARK: - Status transitions

    func testUpdateStatusChangesField() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateStatus(assetId: "a1", status: .uploading)
        XCTAssertEqual(try db.record(for: "a1")?.status, .uploading)
    }

    func testUpdateStatusToUploadedSetsUploadedAt() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateStatus(assetId: "a1", status: .uploaded)
        let fetched = try XCTUnwrap(try db.record(for: "a1"))
        XCTAssertNotNil(fetched.uploadedAt)
        XCTAssertNil(fetched.error, "error should be cleared on successful upload")
    }

    func testUpdateStatusStoresError() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateStatus(assetId: "a1", status: .failed, error: "network timeout")
        XCTAssertEqual(try db.record(for: "a1")?.error, "network timeout")
    }

    func testUpdateStatusToUploadedClearsPreviousError() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateStatus(assetId: "a1", status: .failed, error: "some error")
        try db.updateStatus(assetId: "a1", status: .uploaded)
        XCTAssertNil(try db.record(for: "a1")?.error)
    }

    // MARK: - Retry

    func testIncrementRetryAccumulates() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.incrementRetry(assetId: "a1")
        try db.incrementRetry(assetId: "a1")
        XCTAssertEqual(try db.record(for: "a1")?.retries, 2)
    }

    // MARK: - markPermFailed

    func testMarkPermFailedSetsStatusAndError() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.markPermFailed(assetId: "a1", error: "iCloud unavailable")
        let fetched = try XCTUnwrap(try db.record(for: "a1"))
        XCTAssertEqual(fetched.status, .permFailed)
        XCTAssertEqual(fetched.error, "iCloud unavailable")
    }

    // MARK: - pendingRecords

    func testPendingRecordsExcludesOtherStatuses() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.updateStatus(assetId: "a2", status: .uploaded)
        let pending = try db.pendingRecords()
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].assetId, "a1")
    }

    func testPendingRecordsRespectsLimit() throws {
        for i in 0..<10 { var r = makeRecord("a\(i)"); try db.upsert(&r) }
        XCTAssertEqual(try db.pendingRecords(limit: 3).count, 3)
    }

    // MARK: - resetFailedToPending

    func testResetFailedToPendingResetsBothFailureStatuses() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.updateStatus(assetId: "a1", status: .failed, error: "err")
        try db.markPermFailed(assetId: "a2", error: "perm")
        try db.resetFailedToPending()
        XCTAssertEqual(try db.record(for: "a1")?.status, .pending)
        XCTAssertEqual(try db.record(for: "a2")?.status, .pending)
    }

    func testResetFailedToPendingClearsRetriesAndError() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.incrementRetry(assetId: "a1")
        try db.updateStatus(assetId: "a1", status: .failed, error: "bad")
        try db.resetFailedToPending()
        let fetched = try XCTUnwrap(try db.record(for: "a1"))
        XCTAssertEqual(fetched.retries, 0)
        XCTAssertNil(fetched.error)
    }

    // MARK: - resetStaleUploading

    func testResetStaleUploadingSetsPending() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateStatus(assetId: "a1", status: .uploading)
        try db.resetStaleUploading()
        XCTAssertEqual(try db.record(for: "a1")?.status, .pending)
    }

    func testResetStaleUploadingDoesNotTouchOtherStatuses() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.updateStatus(assetId: "a1", status: .uploaded)
        try db.updateStatus(assetId: "a2", status: .uploading)
        try db.resetStaleUploading()
        XCTAssertEqual(try db.record(for: "a1")?.status, .uploaded, "uploaded records must not be touched")
    }

    // MARK: - Vision metadata

    func testUpdateVisionMetadataStoresAllFields() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateVisionMetadata(assetId: "a1", faceCount: 3, sceneLabels: ["outdoor", "park"], hasText: false)
        let fetched = try XCTUnwrap(try db.record(for: "a1"))
        XCTAssertEqual(fetched.faceCount, 3)
        XCTAssertEqual(fetched.sceneLabelsArray, ["outdoor", "park"])
        XCTAssertFalse(fetched.hasText)
    }

    func testUpdateVisionMetadataWithNilFaceCount() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateVisionMetadata(assetId: "a1", faceCount: nil, sceneLabels: [], hasText: true)
        let fetched = try XCTUnwrap(try db.record(for: "a1"))
        XCTAssertNil(fetched.faceCount)
        XCTAssertTrue(fetched.hasText)
    }

    func testUpdateVisionMetadataEmptyLabelsStoresNilJSON() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateVisionMetadata(assetId: "a1", faceCount: nil, sceneLabels: [], hasText: false)
        let fetched = try XCTUnwrap(try db.record(for: "a1"))
        XCTAssertEqual(fetched.sceneLabelsArray, [])
    }

    // MARK: - stats

    func testStatsCountsMatchInsertedRecords() throws {
        for i in 0..<5 { var r = makeRecord("a\(i)"); try db.upsert(&r) }
        try db.updateStatus(assetId: "a0", status: .uploaded)
        try db.updateStatus(assetId: "a1", status: .uploaded)
        try db.updateStatus(assetId: "a2", status: .uploading)
        try db.updateStatus(assetId: "a3", status: .failed)
        // a4 stays pending

        let stats = try db.stats(totalInLibrary: 10)
        XCTAssertEqual(stats.totalInLibrary, 10)
        XCTAssertEqual(stats.uploaded,  2)
        XCTAssertEqual(stats.uploading, 1)
        XCTAssertEqual(stats.pending,   1)
        XCTAssertEqual(stats.failed,    1)
        XCTAssertEqual(stats.permFailed,0)
    }

    func testStatsLastUploadedAtIsSetAfterUpload() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        let before = Date()
        try db.updateStatus(assetId: "a1", status: .uploaded)
        let after = Date()
        let stats = try db.stats(totalInLibrary: 1)
        let last = try XCTUnwrap(stats.lastUploadedAt)
        XCTAssertTrue(last >= before.addingTimeInterval(-2) && last <= after.addingTimeInterval(2))
    }

    func testStatsEmptyDatabase() throws {
        let stats = try db.stats(totalInLibrary: 50)
        XCTAssertEqual(stats.uploaded,   0)
        XCTAssertEqual(stats.pending,    0)
        XCTAssertNil(stats.lastUploadedAt)
    }

    // MARK: - Helpers

    private func makeRecord(_ assetId: String) -> BackupRecord {
        BackupRecord(assetId: assetId, blobName: "\(assetId).HEIC", mediaType: "image")
    }
}
