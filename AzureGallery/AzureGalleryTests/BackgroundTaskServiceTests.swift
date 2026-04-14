import XCTest
@testable import AzureGallery

/// Tests for BackgroundTaskService constants and smoke-test scheduling.
/// Full BGTaskScheduler integration requires a device; these verify the
/// service's public API surface without triggering real system scheduling.
final class BackgroundTaskServiceTests: XCTestCase {

    func testRefreshIdentifierIsExpectedValue() {
        XCTAssertEqual(
            BackgroundTaskService.refreshIdentifier,
            "com.yogesh.AzureGallery.backgroundRefresh"
        )
    }

    func testScheduleRefreshDoesNotCrash() {
        // Smoke test: calling scheduleRefresh() should not throw or crash,
        // even when BGTaskScheduler hasn't been set up in a test host.
        // The method uses try? internally, so failures are swallowed.
        BackgroundTaskService.scheduleRefresh()
    }
}
