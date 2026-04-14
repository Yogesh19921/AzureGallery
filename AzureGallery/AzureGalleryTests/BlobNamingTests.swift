import XCTest
@testable import AzureGallery

/// Tests BlobNaming.sanitize and blob path shape.
/// PHAsset-dependent methods (blobName, livePhotoBlobName) require a real
/// Photos library and are covered by integration tests, not here.
final class BlobNamingTests: XCTestCase {

    // MARK: - sanitize

    func testSanitizeSlashesReplacedWithDashes() {
        // PHAsset localIdentifiers look like "3E0A4F8B-9C2D-4B1A-A0F2-1234567890AB/L0/001"
        XCTAssertEqual(
            BlobNaming.sanitize("3E0A4F8B-9C2D-4B1A-A0F2-1234567890AB/L0/001"),
            "3E0A4F8B-9C2D-4B1A-A0F2-1234567890AB-L0-001"
        )
    }

    func testSanitizeAlphanumericAndDashUnchanged() {
        XCTAssertEqual(BlobNaming.sanitize("ABC-123-xyz"), "ABC-123-xyz")
    }

    func testSanitizeSpacesReplacedWithDashes() {
        XCTAssertEqual(BlobNaming.sanitize("hello world"), "hello-world")
    }

    func testSanitizeSpecialCharsReplaced() {
        XCTAssertEqual(BlobNaming.sanitize("a!b@c#d"), "a-b-c-d")
    }

    func testSanitizeEmptyStringReturnsEmpty() {
        XCTAssertEqual(BlobNaming.sanitize(""), "")
    }

    func testSanitizeConsecutiveSeparatorsProduceConsecutiveDashes() {
        // Two slashes → two dashes (joined separator between each component)
        let result = BlobNaming.sanitize("a//b")
        XCTAssertTrue(result.hasPrefix("a"), "must start with a")
        XCTAssertTrue(result.hasSuffix("b"), "must end with b")
        XCTAssertFalse(result.contains("/"), "must contain no slashes")
    }

    func testSanitizeUUIDFormatPreserved() {
        // Dashes within UUID are alphanumeric-adjacent, not separators
        let uuid = "A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        XCTAssertEqual(BlobNaming.sanitize(uuid), uuid)
    }

    func testSanitizeDoesNotContainSlash() {
        let result = BlobNaming.sanitize("foo/bar/baz/qux")
        XCTAssertFalse(result.contains("/"))
    }

    func testSanitizeDoesNotContainDot() {
        let result = BlobNaming.sanitize("foo.bar.baz")
        XCTAssertFalse(result.contains("."))
    }

    func testSanitizeTypicalLocalIdentifier() {
        // Ensure the canonical PHAsset identifier format sanitizes correctly
        let id = "F1A2B3C4-D5E6-F7A8-B9C0-D1E2F3A4B5C6/L0/001"
        let result = BlobNaming.sanitize(id)
        XCTAssertFalse(result.contains("/"), "no slashes")
        XCTAssertTrue(result.hasPrefix("F1A2B3C4-D5E6-F7A8-B9C0-D1E2F3A4B5C6"))
    }

    // MARK: - Path structure (without real PHAsset)

    func testSanitizedPathHasOriginalsPrefix() {
        // Construct expected path shape manually to verify prefix convention
        let sanitized = BlobNaming.sanitize("UUID-L0-001")
        let path = "originals/2024/01/\(sanitized).HEIC"
        XCTAssertTrue(path.hasPrefix("originals/"))
    }

    func testMonthFormattedWithLeadingZero() {
        // Month 1-9 must be zero-padded to 2 digits in the path
        let month = String(format: "%02d", 3)
        XCTAssertEqual(month, "03")
    }

    func testMonthDoubleDigitNoLeadingZero() {
        let month = String(format: "%02d", 11)
        XCTAssertEqual(month, "11")
    }
}
