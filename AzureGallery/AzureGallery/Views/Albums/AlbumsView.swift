import SwiftUI
import Photos

struct AlbumsView: View {
    @State private var albumService = SmartAlbumService()
    @State private var selectedAlbum: SmartAlbum?

    var body: some View {
        NavigationStack {
            List {
                if !albumService.peopleAlbums.isEmpty {
                    Section("People & Pets") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(albumService.peopleAlbums) { album in
                                    PersonAlbumCell(album: album)
                                        .onTapGesture { selectedAlbum = album }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                    }
                }

                if !albumService.curatedAlbums.isEmpty {
                    Section("Media Types") {
                        ForEach(albumService.curatedAlbums) { album in
                            Button {
                                selectedAlbum = album
                            } label: {
                                HStack {
                                    Image(systemName: album.systemImage)
                                        .foregroundStyle(.blue)
                                        .frame(width: 28)
                                    Text(album.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(album.assetCount)")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Albums")
            .navigationDestination(item: $selectedAlbum) { album in
                AlbumDetailView(album: album)
            }
            .onAppear { albumService.fetch() }
        }
    }
}

private struct PersonAlbumCell: View {
    let album: SmartAlbum
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(spacing: 6) {
            Group {
                if let img = thumbnail {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay(Image(systemName: "person.fill").foregroundStyle(.secondary))
                }
            }
            .frame(width: 70, height: 70)
            .clipShape(Circle())

            Text(album.title)
                .font(.caption)
                .lineLimit(1)
                .frame(width: 80)

            Text("\(album.assetCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        let assets = PHAsset.fetchAssets(in: album.collection, options: nil)
        guard let first = assets.firstObject else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        PHImageManager.default().requestImage(
            for: first,
            targetSize: CGSize(width: 140, height: 140),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            thumbnail = image
        }
    }
}
