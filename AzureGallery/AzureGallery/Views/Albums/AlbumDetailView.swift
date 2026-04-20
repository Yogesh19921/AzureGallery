import SwiftUI
import Photos

private struct PhotoSelection: Identifiable {
    let id: Int
}

struct AlbumDetailView: View {
    let album: SmartAlbum
    @State private var fetchResult: PHFetchResult<PHAsset>?
    @State private var selectedPhoto: PhotoSelection?

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                if let result = fetchResult {
                    ForEach(0..<result.count, id: \.self) { index in
                        AlbumThumbnailCell(asset: result.object(at: index))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPhoto = PhotoSelection(id: index)
                            }
                    }
                }
            }
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $selectedPhoto) { selection in
            if let result = fetchResult {
                var arr: [PHAsset] = []
                arr.reserveCapacity(result.count)
                result.enumerateObjects { asset, _, _ in arr.append(asset) }
                return AnyView(PhotoDetailView(assets: arr, currentIndex: selection.id))
            }
            return AnyView(EmptyView())
        }
        .onAppear {
            let options = PHFetchOptions()
            options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchResult = PHAsset.fetchAssets(in: album.collection, options: options)
        }
    }
}

private struct AlbumThumbnailCell: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage?

    var body: some View {
        Group {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle().fill(Color(.systemGray5))
            }
        }
        .frame(width: cellSize, height: cellSize)
        .clipped()
        .overlay(alignment: .bottomLeading) {
            if asset.mediaType == .video {
                Image(systemName: "video.fill")
                    .font(.caption2)
                    .foregroundStyle(.white)
                    .padding(4)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            BackupCloudBadge(assetId: asset.localIdentifier)
                .padding(4)
        }
        .onAppear { loadThumbnail() }
    }

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 4) / 3 }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 220, height: 220),
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result {
                DispatchQueue.main.async { thumbnail = result }
            }
        }
    }
}
