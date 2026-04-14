import SwiftUI
import Photos

struct GalleryView: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var selectedIndex: Int?
    @State private var showDetail = false

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            Group {
                switch photoLibrary.authorizationStatus {
                case .authorized, .limited:
                    photoGrid
                case .denied, .restricted:
                    ContentUnavailableView(
                        "No Photo Access",
                        systemImage: "photo.slash",
                        description: Text("Enable photo library access in Settings.")
                    )
                case .notDetermined:
                    VStack(spacing: 16) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("Grant access to your photo library to get started.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Button("Allow Access") {
                            Task { await photoLibrary.requestAuthorization() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                @unknown default:
                    EmptyView()
                }
            }
            .navigationTitle("Gallery")
        }
        .fullScreenCover(isPresented: $showDetail) {
            if let index = selectedIndex {
                PhotoDetailView(assets: assetArray(), currentIndex: index)
            }
        }
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<photoLibrary.assets.count, id: \.self) { index in
                    ThumbnailCell(asset: photoLibrary.assets[index])
                        .onTapGesture {
                            selectedIndex = index
                            showDetail = true
                        }
                }
            }
        }
    }

    private func assetArray() -> [PHAsset] {
        var result: [PHAsset] = []
        result.reserveCapacity(photoLibrary.assets.count)
        photoLibrary.assets.enumerateObjects { a, _, _ in result.append(a) }
        return result
    }
}

private struct ThumbnailCell: View {
    let asset: PHAsset
    @State private var thumbnail: UIImage?
    private static let size = CGSize(width: 220, height: 220)

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
        .onAppear { loadThumbnail() }
    }

    private var cellSize: CGFloat {
        (UIScreen.main.bounds.width - 4) / 3
    }

    private func loadThumbnail() {
        guard thumbnail == nil else { return }
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: Self.size,
            contentMode: .aspectFill,
            options: options
        ) { result, _ in
            if let result { thumbnail = result }
        }
    }
}
