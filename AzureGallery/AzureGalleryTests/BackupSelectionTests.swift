import XCTest
@testable import AzureGallery

/// Tests BackupSelectionService.allowedAssetIds() edge cases.
/// PhotoKit is not available in the test host, so we test the guard logic
/// by manipulating the public state directly on the shared singleton.
final class BackupSelectionTests: XCTestCase {

    private let svc = BackupSelectionService.shared

    // Save original state so we can restore after each test.
    private var origAll = true
    private var origAlbums: Set<String> = []

    override func setUp() {
        super.setUp()
        origAll = svc.backupAllPhotos
        origAlbums = svc.selectedAlbumIds
    }

    override func tearDown() {
        svc.backupAllPhotos = origAll
        svc.selectedAlbumIds = origAlbums
        super.tearDown()
    }

    // MARK: - allowedAssetIds guard logic

    func testAllPhotosOnReturnsNil() {
        svc.backupAllPhotos = true
        svc.selectedAlbumIds = ["some-album"]
        XCTAssertNil(svc.allowedAssetIds(), "nil means 'back up everything'")
    }

    func testAllPhotosOffNoAlbumsReturnsEmptySet() {
        svc.backupAllPhotos = false
        svc.selectedAlbumIds = []
        let result = svc.allowedAssetIds()
        XCTAssertNotNil(result, "Should return an empty set, not nil")
        XCTAssertTrue(result!.isEmpty, "No albums selected → empty allowed set → back up nothing")
    }

    func testAllPhotosOffWithAlbumsReturnsNonNil() {
        // We can't guarantee the album IDs map to real PhotoKit collections in tests,
        // so the returned set may be empty (no matching assets). But it must NOT be nil.
        svc.backupAllPhotos = false
        svc.selectedAlbumIds = ["fake-album-id"]
        let result = svc.allowedAssetIds()
        XCTAssertNotNil(result, "Must return a Set (possibly empty) when albums are selected")
    }

    // MARK: - toggle

    func testToggleAddsAndRemoves() {
        svc.selectedAlbumIds = []
        svc.toggle(albumId: "x")
        XCTAssertTrue(svc.selectedAlbumIds.contains("x"))
        svc.toggle(albumId: "x")
        XCTAssertFalse(svc.selectedAlbumIds.contains("x"))
    }

    // MARK: - isSelected

    func testIsSelectedTrueWhenAllPhotosOn() {
        svc.backupAllPhotos = true
        svc.selectedAlbumIds = []
        XCTAssertTrue(svc.isSelected("any-id"), "All photos on → every album is selected")
    }

    func testIsSelectedFalseWhenNotInSet() {
        svc.backupAllPhotos = false
        svc.selectedAlbumIds = ["other"]
        XCTAssertFalse(svc.isSelected("not-in-set"))
    }

    func testIsSelectedTrueWhenInSet() {
        svc.backupAllPhotos = false
        svc.selectedAlbumIds = ["target"]
        XCTAssertTrue(svc.isSelected("target"))
    }
}
