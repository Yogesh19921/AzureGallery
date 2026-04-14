import XCTest
@testable import AzureGallery

final class BackupStatsTests: XCTestCase {

    func testPendingTotalSumsPendingAndUploading() {
        let s = BackupStats(totalInLibrary: 100, uploaded: 50, pending: 30,
                            uploading: 5, failed: 10, permFailed: 5, lastUploadedAt: nil,
                            bytesToday: 0, bytesThisMonth: 0)
        XCTAssertEqual(s.pendingTotal, 35)
    }

    func testAllFailedSumsFailedAndPermFailed() {
        let s = BackupStats(totalInLibrary: 100, uploaded: 50, pending: 30,
                            uploading: 5, failed: 10, permFailed: 5, lastUploadedAt: nil,
                            bytesToday: 0, bytesThisMonth: 0)
        XCTAssertEqual(s.allFailed, 15)
    }

    func testPendingTotalWhenAllZero() {
        XCTAssertEqual(BackupStats.empty.pendingTotal, 0)
    }

    func testAllFailedWhenAllZero() {
        XCTAssertEqual(BackupStats.empty.allFailed, 0)
    }

    func testEmptyHasNoLastUploadedAt() {
        XCTAssertNil(BackupStats.empty.lastUploadedAt)
    }

    func testEmptyHasZeroTotalInLibrary() {
        XCTAssertEqual(BackupStats.empty.totalInLibrary, 0)
    }

    func testAllFieldsOnEmpty() {
        let e = BackupStats.empty
        XCTAssertEqual(e.uploaded,   0)
        XCTAssertEqual(e.pending,    0)
        XCTAssertEqual(e.uploading,  0)
        XCTAssertEqual(e.failed,     0)
        XCTAssertEqual(e.permFailed, 0)
    }
}
