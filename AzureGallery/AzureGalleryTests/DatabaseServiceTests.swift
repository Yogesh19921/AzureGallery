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

    // MARK: - purgeNonUploadedNotIn

    func testPurgeWithNilDoesNothing() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.purgeNonUploadedNotIn(allowedIds: nil)
        XCTAssertNotNil(try db.record(for: "a1"), "nil = all allowed, nothing should be purged")
    }

    func testPurgeWithEmptySetDeletesAllNonUploaded() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2"); var r3 = makeRecord("a3")
        try db.upsert(&r1); try db.upsert(&r2); try db.upsert(&r3)
        try db.updateStatus(assetId: "a2", status: .uploaded)
        try db.purgeNonUploadedNotIn(allowedIds: Set())
        XCTAssertNil(try db.record(for: "a1"), "pending record should be purged")
        XCTAssertNotNil(try db.record(for: "a2"), "uploaded record must survive")
        XCTAssertNil(try db.record(for: "a3"), "pending record should be purged")
    }

    func testPurgeKeepsAllowedPendingRecords() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2"); var r3 = makeRecord("a3")
        try db.upsert(&r1); try db.upsert(&r2); try db.upsert(&r3)
        try db.purgeNonUploadedNotIn(allowedIds: ["a1", "a3"])
        XCTAssertNotNil(try db.record(for: "a1"))
        XCTAssertNil(try db.record(for: "a2"), "a2 is not in allowed set")
        XCTAssertNotNil(try db.record(for: "a3"))
    }

    func testPurgeKeepsUploadedEvenWhenNotInAllowed() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateStatus(assetId: "a1", status: .uploaded)
        try db.purgeNonUploadedNotIn(allowedIds: Set())
        XCTAssertNotNil(try db.record(for: "a1"), "uploaded records must never be purged")
    }

    func testPurgeDeletesFailedRecordsNotInAllowed() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateStatus(assetId: "a1", status: .failed, error: "err")
        try db.purgeNonUploadedNotIn(allowedIds: ["other"])
        XCTAssertNil(try db.record(for: "a1"))
    }

    func testPurgeDeletesPermFailedNotInAllowed() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.markPermFailed(assetId: "a1", error: "done")
        try db.purgeNonUploadedNotIn(allowedIds: ["other"])
        XCTAssertNil(try db.record(for: "a1"))
    }

    func testPurgeDoesNotDeleteUploadingRecords() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateStatus(assetId: "a1", status: .uploading)
        try db.purgeNonUploadedNotIn(allowedIds: Set())
        XCTAssertNotNil(try db.record(for: "a1"), "uploading records must not be purged mid-flight")
    }

    // MARK: - uploadedRecords

    func testUploadedRecordsReturnsOnlyUploaded() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2"); var r3 = makeRecord("a3")
        try db.upsert(&r1); try db.upsert(&r2); try db.upsert(&r3)
        try db.updateStatus(assetId: "a1", status: .uploaded)
        try db.updateStatus(assetId: "a3", status: .uploaded)
        let uploaded = try db.uploadedRecords()
        let ids = Set(uploaded.map(\.assetId))
        XCTAssertEqual(ids, ["a1", "a3"])
    }

    func testUploadedRecordsEmptyWhenNoneUploaded() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        XCTAssertTrue(try db.uploadedRecords().isEmpty)
    }

    // MARK: - pendingCount

    func testPendingCountReturnsZeroForEmptyDB() throws {
        XCTAssertEqual(try db.pendingCount(), 0)
    }

    func testPendingCountReturnsCorrectCount() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2"); var r3 = makeRecord("a3")
        try db.upsert(&r1); try db.upsert(&r2); try db.upsert(&r3)
        // All three start as pending
        XCTAssertEqual(try db.pendingCount(), 3)
    }

    func testPendingCountExcludesOtherStatuses() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        var r3 = makeRecord("a3"); var r4 = makeRecord("a4")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.upsert(&r3); try db.upsert(&r4)
        try db.updateStatus(assetId: "a1", status: .uploaded)
        try db.updateStatus(assetId: "a2", status: .uploading)
        try db.updateStatus(assetId: "a3", status: .failed, error: "err")
        // Only a4 remains pending
        XCTAssertEqual(try db.pendingCount(), 1)
    }

    func testPendingCountAfterResetFailedToPending() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.updateStatus(assetId: "a1", status: .failed, error: "err")
        try db.markPermFailed(assetId: "a2", error: "perm")
        // 0 pending before reset
        XCTAssertEqual(try db.pendingCount(), 0)
        try db.resetFailedToPending()
        // Both should now be pending
        XCTAssertEqual(try db.pendingCount(), 2)
    }

    // MARK: - searchRecords

    func testSearchByHasText() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.updateVisionMetadata(assetId: "a1", faceCount: nil, sceneLabels: [], hasText: true)
        try db.updateVisionMetadata(assetId: "a2", faceCount: nil, sceneLabels: [], hasText: false)
        let results = try db.searchRecords(hasText: true)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].assetId, "a1")
    }

    func testSearchByMinFaces() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2"); var r3 = makeRecord("a3")
        try db.upsert(&r1); try db.upsert(&r2); try db.upsert(&r3)
        try db.updateVisionMetadata(assetId: "a1", faceCount: 1, sceneLabels: [], hasText: false)
        try db.updateVisionMetadata(assetId: "a2", faceCount: 3, sceneLabels: [], hasText: false)
        try db.updateVisionMetadata(assetId: "a3", faceCount: nil, sceneLabels: [], hasText: false)
        let results = try db.searchRecords(minFaces: 2)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].assetId, "a2")
    }

    func testSearchBySceneKeyword() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.updateVisionMetadata(assetId: "a1", faceCount: nil, sceneLabels: ["outdoor", "park"], hasText: false)
        try db.updateVisionMetadata(assetId: "a2", faceCount: nil, sceneLabels: ["indoor", "office"], hasText: false)
        let results = try db.searchRecords(sceneKeyword: "outdoor")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].assetId, "a1")
    }

    func testSearchNoMatchesReturnsEmpty() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateVisionMetadata(assetId: "a1", faceCount: nil, sceneLabels: [], hasText: false)
        let results = try db.searchRecords(sceneKeyword: "beach")
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchCombinedFilters() throws {
        var r1 = makeRecord("a1"); var r2 = makeRecord("a2")
        try db.upsert(&r1); try db.upsert(&r2)
        try db.updateVisionMetadata(assetId: "a1", faceCount: 2, sceneLabels: ["outdoor"], hasText: true)
        try db.updateVisionMetadata(assetId: "a2", faceCount: 1, sceneLabels: ["outdoor"], hasText: false)
        let results = try db.searchRecords(hasText: true, minFaces: 2, sceneKeyword: "outdoor")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].assetId, "a1")
    }

    func testSearchRespectsLimit() throws {
        for i in 0..<10 {
            var r = makeRecord("a\(i)"); try db.upsert(&r)
            try db.updateVisionMetadata(assetId: "a\(i)", faceCount: nil, sceneLabels: ["outdoor"], hasText: false)
        }
        let results = try db.searchRecords(sceneKeyword: "outdoor", limit: 3)
        XCTAssertEqual(results.count, 3)
    }

    // MARK: - Content Hash

    func testRecordByHashReturnsNilWhenNoMatch() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        XCTAssertNil(try db.recordByHash(hash: "abc123"))
    }

    func testRecordByHashReturnsRecordWhenMatches() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateHash(assetId: "a1", hash: "deadbeef")
        let found = try XCTUnwrap(try db.recordByHash(hash: "deadbeef"))
        XCTAssertEqual(found.assetId, "a1")
    }

    func testUpdateHashPersistsCorrectly() throws {
        var r = makeRecord("a1"); try db.upsert(&r)
        try db.updateHash(assetId: "a1", hash: "sha256hash")
        let fetched = try XCTUnwrap(try db.record(for: "a1"))
        XCTAssertEqual(fetched.contentHash, "sha256hash")
    }

    // MARK: - Bandwidth Stats

    func testRecordUploadAndBytesUploadedToday() throws {
        try db.recordUpload(bytes: 1_000, date: Date())
        try db.recordUpload(bytes: 2_500, date: Date())
        XCTAssertEqual(try db.bytesUploadedToday(), 3_500)
    }

    func testBytesUploadedThisMonthSpansFullMonth() throws {
        // Record uploads spread across different days in the current month
        let cal = Calendar(identifier: .gregorian)
        let now = Date()
        let components = cal.dateComponents([.year, .month], from: now)
        // First day of current month
        let firstOfMonth = cal.date(from: components)!
        // A day mid-month (or first + 1 day if early in the month)
        let midMonth = cal.date(byAdding: .day, value: 1, to: firstOfMonth)!

        try db.recordUpload(bytes: 500, date: firstOfMonth)
        try db.recordUpload(bytes: 700, date: midMonth)
        try db.recordUpload(bytes: 300, date: now)
        XCTAssertEqual(try db.bytesUploadedThisMonth(), 1_500)
    }

    func testBytesUploadedTodayExcludesOtherDays() throws {
        // Record an upload "yesterday"
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        try db.recordUpload(bytes: 999, date: yesterday)
        try db.recordUpload(bytes: 100, date: Date())
        XCTAssertEqual(try db.bytesUploadedToday(), 100)
    }

    func testBytesUploadedTodayReturnsZeroWhenEmpty() throws {
        XCTAssertEqual(try db.bytesUploadedToday(), 0)
    }

    func testBytesUploadedThisMonthReturnsZeroWhenEmpty() throws {
        XCTAssertEqual(try db.bytesUploadedThisMonth(), 0)
    }

    // MARK: - Helpers

    private func makeRecord(_ assetId: String) -> BackupRecord {
        BackupRecord(assetId: assetId, blobName: "\(assetId).HEIC", mediaType: "image")
    }
}
