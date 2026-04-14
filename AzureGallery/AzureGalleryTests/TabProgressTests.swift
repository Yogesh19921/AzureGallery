import XCTest
@testable import AzureGallery

/// Tests for the `circularProgressImage` utility function that renders
/// a circular progress indicator as a UIImage for the tab bar.
final class TabProgressTests: XCTestCase {

    func testProgressZeroReturnsNonNilImage() {
        let image = circularProgressImage(progress: 0)
        XCTAssertNotNil(image)
    }

    func testProgressHalfReturnsNonNilImage() {
        let image = circularProgressImage(progress: 0.5)
        XCTAssertNotNil(image)
    }

    func testProgressFullReturnsNonNilImage() {
        let image = circularProgressImage(progress: 1.0)
        XCTAssertNotNil(image)
    }

    func testImageSizeMatchesDefaultSize() {
        let image = circularProgressImage(progress: 0.5)
        // Default size is 25x25
        XCTAssertEqual(image.size.width, 25, accuracy: 0.1)
        XCTAssertEqual(image.size.height, 25, accuracy: 0.1)
    }

    func testImageSizeMatchesCustomSize() {
        let image = circularProgressImage(progress: 0.5, size: 50)
        XCTAssertEqual(image.size.width, 50, accuracy: 0.1)
        XCTAssertEqual(image.size.height, 50, accuracy: 0.1)
    }

    func testProgressClampedAboveOne() {
        // Should not crash when progress > 1
        let image = circularProgressImage(progress: 1.5)
        XCTAssertNotNil(image)
    }

    func testProgressClampedBelowZero() {
        // Should not crash when progress < 0
        let image = circularProgressImage(progress: -0.5)
        XCTAssertNotNil(image)
    }
}
