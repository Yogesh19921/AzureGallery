import XCTest
@testable import AzureGallery

/// Smoke tests for NotificationService — verifies the API surface is callable.
/// Actual notification delivery requires a running app with user permission,
/// so these tests only confirm the methods exist and do not crash.
final class NotificationServiceTests: XCTestCase {

    @MainActor
    func testRequestPermissionDoesNotCrash() {
        // Calling requestPermission in a test environment won't show a prompt
        // but should not throw or crash.
        NotificationService.requestPermission()
    }

    func testUpdateBadgeMethodExists() {
        // setBadgeCount is a no-op in the test host, but should not crash.
        NotificationService.updateBadge(count: 0)
    }

    func testPostBatchCompleteDoesNotCrash() {
        // Posting a notification request in a test host will silently fail delivery,
        // but the method should not throw.
        NotificationService.postBatchComplete(uploadedCount: 5)
    }
}
