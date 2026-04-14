import XCTest
@testable import AzureGallery

final class OnboardingTests: XCTestCase {

    private let key = "hasCompletedOnboarding"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testHasCompletedOnboardingDefaultsToFalse() {
        // Remove any existing value to simulate a fresh install
        UserDefaults.standard.removeObject(forKey: key)
        let value = UserDefaults.standard.bool(forKey: key)
        XCTAssertFalse(value, "hasCompletedOnboarding should default to false on fresh install")
    }

    func testSettingHasCompletedOnboardingToTruePersists() {
        UserDefaults.standard.set(true, forKey: key)
        let value = UserDefaults.standard.bool(forKey: key)
        XCTAssertTrue(value, "hasCompletedOnboarding should persist as true after being set")
    }

    func testSettingHasCompletedOnboardingBackToFalse() {
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.set(false, forKey: key)
        let value = UserDefaults.standard.bool(forKey: key)
        XCTAssertFalse(value, "hasCompletedOnboarding should be resettable to false")
    }

    func testRemovingKeyResetsToDefault() {
        UserDefaults.standard.set(true, forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        let value = UserDefaults.standard.bool(forKey: key)
        XCTAssertFalse(value, "Removing the key should revert to the default false value")
    }
}
