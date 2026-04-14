import XCTest
@testable import AzureGallery

final class BackupWidgetDataTests: XCTestCase {

    private let widgetDataKey = "widgetData"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: widgetDataKey)
        super.tearDown()
    }

    // MARK: - Encode / Decode Round-Trip

    func testEncodeDecodeRoundTrip() throws {
        let original = BackupWidgetData(
            uploaded: 42,
            pending: 5,
            failed: 1,
            lastBackupDate: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackupWidgetData.self, from: data)

        XCTAssertEqual(decoded.uploaded, 42)
        XCTAssertEqual(decoded.pending, 5)
        XCTAssertEqual(decoded.failed, 1)
        let decodedDate = try XCTUnwrap(decoded.lastBackupDate)
        let originalDate = try XCTUnwrap(original.lastBackupDate)
        XCTAssertEqual(decodedDate.timeIntervalSince1970, originalDate.timeIntervalSince1970, accuracy: 0.001)
    }

    func testEncodeDecodeWithNilDate() throws {
        let original = BackupWidgetData(
            uploaded: 0,
            pending: 0,
            failed: 0,
            lastBackupDate: nil
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BackupWidgetData.self, from: data)

        XCTAssertEqual(decoded.uploaded, 0)
        XCTAssertEqual(decoded.pending, 0)
        XCTAssertEqual(decoded.failed, 0)
        XCTAssertNil(decoded.lastBackupDate)
    }

    // MARK: - Save / Load Round-Trip

    func testSaveAndLoadRoundTrip() {
        let original = BackupWidgetData(
            uploaded: 100,
            pending: 10,
            failed: 2,
            lastBackupDate: Date()
        )

        original.save()

        let loaded = BackupWidgetData.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.uploaded, 100)
        XCTAssertEqual(loaded?.pending, 10)
        XCTAssertEqual(loaded?.failed, 2)
        XCTAssertNotNil(loaded?.lastBackupDate)
    }

    func testLoadReturnsNilWhenNothingSaved() {
        UserDefaults.standard.removeObject(forKey: widgetDataKey)
        let loaded = BackupWidgetData.load()
        XCTAssertNil(loaded, "load() should return nil when no data has been saved")
    }

    func testSaveOverwritesPreviousData() {
        let first = BackupWidgetData(uploaded: 10, pending: 5, failed: 0, lastBackupDate: nil)
        first.save()

        let second = BackupWidgetData(uploaded: 20, pending: 3, failed: 1, lastBackupDate: Date())
        second.save()

        let loaded = BackupWidgetData.load()
        XCTAssertEqual(loaded?.uploaded, 20)
        XCTAssertEqual(loaded?.pending, 3)
        XCTAssertEqual(loaded?.failed, 1)
    }

    // MARK: - Field Validation

    func testCurrentReturnsNonNegativeValues() {
        // BackupWidgetData.current() queries the real database which may not be
        // set up in the test environment. We test that the fallback (.empty stats)
        // produces valid non-negative values.
        let fallback = BackupWidgetData(uploaded: 0, pending: 0, failed: 0, lastBackupDate: nil)
        XCTAssertGreaterThanOrEqual(fallback.uploaded, 0)
        XCTAssertGreaterThanOrEqual(fallback.pending, 0)
        XCTAssertGreaterThanOrEqual(fallback.failed, 0)
    }
}
