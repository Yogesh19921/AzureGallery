import XCTest
@testable import AzureGallery

/// Tests the pure `shouldAllowUpload` function on `BackupEngine`.
/// All four combinations of wifiOnly / chargeOnly with matching conditions.
final class NetworkMonitorTests: XCTestCase {

    // MARK: - shouldAllowUpload

    func testAllowsUploadWhenNoPolicyEnabled() {
        XCTAssertTrue(
            BackupEngine.shouldAllowUpload(wifiOnly: false, chargeOnly: false,
                                            isCellular: true, isCharging: false)
        )
    }

    func testBlocksUploadWhenWifiOnlyAndCellular() {
        XCTAssertFalse(
            BackupEngine.shouldAllowUpload(wifiOnly: true, chargeOnly: false,
                                            isCellular: true, isCharging: true)
        )
    }

    func testAllowsUploadWhenWifiOnlyAndNotCellular() {
        XCTAssertTrue(
            BackupEngine.shouldAllowUpload(wifiOnly: true, chargeOnly: false,
                                            isCellular: false, isCharging: false)
        )
    }

    func testBlocksUploadWhenChargeOnlyAndNotCharging() {
        XCTAssertFalse(
            BackupEngine.shouldAllowUpload(wifiOnly: false, chargeOnly: true,
                                            isCellular: false, isCharging: false)
        )
    }

    func testAllowsUploadWhenChargeOnlyAndCharging() {
        XCTAssertTrue(
            BackupEngine.shouldAllowUpload(wifiOnly: false, chargeOnly: true,
                                            isCellular: false, isCharging: true)
        )
    }

    func testBlocksUploadWhenBothPoliciesViolated() {
        XCTAssertFalse(
            BackupEngine.shouldAllowUpload(wifiOnly: true, chargeOnly: true,
                                            isCellular: true, isCharging: false)
        )
    }

    func testBlocksUploadWhenWifiOnlyViolatedButChargingMet() {
        XCTAssertFalse(
            BackupEngine.shouldAllowUpload(wifiOnly: true, chargeOnly: true,
                                            isCellular: true, isCharging: true)
        )
    }

    func testBlocksUploadWhenChargeOnlyViolatedButWifiMet() {
        XCTAssertFalse(
            BackupEngine.shouldAllowUpload(wifiOnly: true, chargeOnly: true,
                                            isCellular: false, isCharging: false)
        )
    }

    func testAllowsUploadWhenBothPoliciesSatisfied() {
        XCTAssertTrue(
            BackupEngine.shouldAllowUpload(wifiOnly: true, chargeOnly: true,
                                            isCellular: false, isCharging: true)
        )
    }
}
