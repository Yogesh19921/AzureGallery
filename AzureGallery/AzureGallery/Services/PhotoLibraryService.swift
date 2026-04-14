import Foundation
import Photos
import Observation

/// Observable wrapper around the Photos framework.
///
/// Loads the full photo library into `assets` and registers as a `PHPhotoLibraryChangeObserver`
/// to detect newly added assets in real time. The `onNewAssets` callback notifies
/// `BackupEngine` so new photos are queued immediately without a full rescan.
@Observable
final class PhotoLibraryService: NSObject {
    private(set) var authorizationStatus: PHAuthorizationStatus = .notDetermined
    private(set) var assets: PHFetchResult<PHAsset> = PHFetchResult()
    private(set) var totalCount: Int = 0

    /// Called on the main thread whenever new assets are inserted into the library.
    var onNewAssets: (([PHAsset]) -> Void)?

    override init() {
        super.init()
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Request `.readWrite` authorization. On grant, fetches assets and registers the change observer.
    func requestAuthorization() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run { authorizationStatus = status }
        if status == .authorized || status == .limited {
            await fetchAssets()
            PHPhotoLibrary.shared().register(self)
        }
    }

    /// (Re)fetch all assets from PhotoKit, sorted newest-first. Must run on the main actor.
    @MainActor
    func fetchAssets() async {
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssets(with: fetchOptions)
        assets = result
        totalCount = result.count
    }

    func asset(for localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    // Returns all local identifiers currently in the library
    func allLocalIdentifiers() -> [String] {
        var ids: [String] = []
        ids.reserveCapacity(assets.count)
        assets.enumerateObjects { asset, _, _ in ids.append(asset.localIdentifier) }
        return ids
    }
}

extension PhotoLibraryService: PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        guard let changes = changeInstance.changeDetails(for: assets) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.assets = changes.fetchResultAfterChanges
            self.totalCount = self.assets.count

            let inserted = changes.insertedObjects
            if !inserted.isEmpty {
                self.onNewAssets?(inserted)
            }
        }
    }
}
