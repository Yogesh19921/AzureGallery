import XCTest
@testable import AzureGallery

/// Tests for DeviceIdentifier — stable, short device ID persisted in UserDefaults.
final class DeviceIdentifierTests: XCTestCase {

    func testCurrentReturnsNonEmptyString() {
        let id = DeviceIdentifier.current
        XCTAssertFalse(id.isEmpty, "Device identifier must not be empty")
    }

    func testCurrentIsStableAcrossCalls() {
        let first = DeviceIdentifier.current
        let second = DeviceIdentifier.current
        XCTAssertEqual(first, second, "Device identifier must be stable across calls")
    }

    func testCurrentIsAtMostEightCharacters() {
        let id = DeviceIdentifier.current
        XCTAssertLessThanOrEqual(id.count, 8, "Device identifier must be <= 8 characters")
    }

    func testCurrentIsLowercase() {
        let id = DeviceIdentifier.current
        XCTAssertEqual(id, id.lowercased(), "Device identifier should be lowercase")
    }
}
