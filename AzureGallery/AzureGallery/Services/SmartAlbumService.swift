import Foundation
import Photos
import Observation

struct SmartAlbum: Identifiable, Hashable {
    static func == (lhs: SmartAlbum, rhs: SmartAlbum) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let id: String
    let title: String
    let systemImage: String
    let collection: PHAssetCollection
    var assetCount: Int
}

@Observable
final class SmartAlbumService {
    private(set) var peopleAlbums: [SmartAlbum] = []
    private(set) var curatedAlbums: [SmartAlbum] = []   // selfies, screenshots, etc.

    func fetch() {
        peopleAlbums = fetchPeople()
        curatedAlbums = fetchCurated()
    }

    func assets(for album: SmartAlbum) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return PHAsset.fetchAssets(in: album.collection, options: options)
    }

    // MARK: - Private

    private func fetchPeople() -> [SmartAlbum] {
        var albums: [SmartAlbum] = []
        let result = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumRegular,  // People albums appear here on some OS versions
            options: nil
        )
        // Primary: smartAlbumPeople (iOS 15+)
        // smartAlbumPeople requires iOS 16+ and face grouping to be enabled in Photos
        if #available(iOS 16, *) {
            let smartPeople = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum,
                subtype: PHAssetCollectionSubtype(rawValue: 211) ?? .smartAlbumUserLibrary, // people subtype raw value
                options: nil
            )
            smartPeople.enumerateObjects { collection, _, _ in
                let count = PHAsset.fetchAssets(in: collection, options: nil).count
                guard count > 0 else { return }
                albums.append(SmartAlbum(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Person",
                    systemImage: "person.crop.circle",
                    collection: collection,
                    assetCount: count
                ))
            }
        }
        _ = result  // suppress unused warning
        return albums
    }

    private func fetchCurated() -> [SmartAlbum] {
        let definitions: [(subtype: PHAssetCollectionSubtype, title: String, icon: String)] = [
            (.smartAlbumSelfPortraits,  "Selfies",      "camera.on.rectangle"),
            (.smartAlbumScreenshots,   "Screenshots",  "iphone"),
            (.smartAlbumPanoramas,     "Panoramas",    "panorama"),
            (.smartAlbumLivePhotos,    "Live Photos",  "livephoto"),
            (.smartAlbumAnimated,      "Animated",     "play.circle"),
            (.smartAlbumBursts,        "Bursts",       "square.stack.3d.up"),
            (.smartAlbumFavorites,     "Favorites",    "heart"),
            (.smartAlbumVideos,        "Videos",       "video"),
            (.smartAlbumSlomoVideos,   "Slo-Mo",       "gauge.with.dots.needle.33percent"),
            (.smartAlbumTimelapses,    "Timelapses",   "timelapse"),
            (.smartAlbumDepthEffect,   "Portrait",     "camera.aperture"),
        ]

        return definitions.compactMap { def in
            let result = PHAssetCollection.fetchAssetCollections(
                with: .smartAlbum, subtype: def.subtype, options: nil
            )
            guard let collection = result.firstObject else { return nil }
            let count = PHAsset.fetchAssets(in: collection, options: nil).count
            guard count > 0 else { return nil }
            return SmartAlbum(
                id: collection.localIdentifier,
                title: def.title,
                systemImage: def.icon,
                collection: collection,
                assetCount: count
            )
        }
    }
}
