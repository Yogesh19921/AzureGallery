import Foundation
import Photos
import Observation

private let selectedAlbumsKey = "BackupSelection.selectedAlbumIds"
private let allPhotosKey = "BackupSelection.allPhotos"

/// Persists the user's backup scope selection (all photos vs. specific albums).
///
/// `BackupEngine` calls ``allowedAssetIds()`` before queuing assets. A `nil` return
/// means "back up everything" — this is the fast path that avoids loading album contents.
@Observable
final class BackupSelectionService {
    static let shared = BackupSelectionService()

    /// When true, all photos in the library are backed up regardless of album selection.
    var backupAllPhotos: Bool {
        didSet { UserDefaults.standard.set(backupAllPhotos, forKey: allPhotosKey) }
    }

    /// Album `localIdentifier` values selected for backup. Only used when `backupAllPhotos` is false.
    var selectedAlbumIds: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(selectedAlbumIds), forKey: selectedAlbumsKey)
        }
    }

    private(set) var availableAlbums: [SelectableAlbum] = []

    private init() {
        let stored = UserDefaults.standard.object(forKey: allPhotosKey)
        backupAllPhotos = stored == nil ? true : UserDefaults.standard.bool(forKey: allPhotosKey)
        let ids = UserDefaults.standard.stringArray(forKey: selectedAlbumsKey) ?? []
        selectedAlbumIds = Set(ids)
    }

    // MARK: - Album loading

    /// Populate `availableAlbums` from PhotoKit. Includes user albums and key smart albums.
    func loadAvailableAlbums() {
        var albums: [SelectableAlbum] = []

        // User-created albums
        let userAlbums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        userAlbums.enumerateObjects { col, _, _ in
            let count = PHAsset.fetchAssets(in: col, options: nil).count
            guard count > 0 else { return }
            albums.append(SelectableAlbum(
                id: col.localIdentifier,
                title: col.localizedTitle ?? "Untitled",
                systemImage: "folder",
                assetCount: count,
                isSmartAlbum: false
            ))
        }

        // Key smart albums
        let smartDefs: [(PHAssetCollectionSubtype, String, String)] = [
            (.smartAlbumSelfPortraits, "Selfies",     "camera.on.rectangle"),
            (.smartAlbumScreenshots,  "Screenshots", "iphone"),
            (.smartAlbumPanoramas,    "Panoramas",   "panorama"),
            (.smartAlbumLivePhotos,   "Live Photos", "livephoto"),
            (.smartAlbumFavorites,    "Favorites",   "heart"),
            (.smartAlbumVideos,       "Videos",      "video"),
            (.smartAlbumBursts,       "Bursts",      "square.stack.3d.up"),
        ]
        for (subtype, title, icon) in smartDefs {
            let result = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: subtype, options: nil)
            guard let col = result.firstObject else { continue }
            let count = PHAsset.fetchAssets(in: col, options: nil).count
            guard count > 0 else { continue }
            albums.append(SelectableAlbum(
                id: col.localIdentifier,
                title: title,
                systemImage: icon,
                assetCount: count,
                isSmartAlbum: true
            ))
        }

        availableAlbums = albums.sorted { $0.title < $1.title }
    }

    // MARK: - Query

    func toggle(albumId: String) {
        if selectedAlbumIds.contains(albumId) {
            selectedAlbumIds.remove(albumId)
        } else {
            selectedAlbumIds.insert(albumId)
        }
    }

    func isSelected(_ albumId: String) -> Bool {
        backupAllPhotos || selectedAlbumIds.contains(albumId)
    }

    /// Returns the set of PHAsset localIdentifiers allowed for backup.
    /// Returns nil if all photos should be backed up (fast path).
    func allowedAssetIds() -> Set<String>? {
        guard !backupAllPhotos, !selectedAlbumIds.isEmpty else { return nil }

        var allowed = Set<String>()
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: Array(selectedAlbumIds), options: nil
        )
        collections.enumerateObjects { col, _, _ in
            let assets = PHAsset.fetchAssets(in: col, options: nil)
            assets.enumerateObjects { asset, _, _ in
                allowed.insert(asset.localIdentifier)
            }
        }
        return allowed
    }
}

struct SelectableAlbum: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let assetCount: Int
    let isSmartAlbum: Bool
}
