import SwiftUI
import Photos

// Identifiable wrapper so we can use fullScreenCover(item:)
private struct PhotoSelection: Identifiable {
    let id: Int // index into fetchResult
}

struct GalleryView: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var selectedPhoto: PhotoSelection?

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
            .fullScreenCover(item: $selectedPhoto) { selection in
                PhotoDetailView(fetchResult: photoLibrary.assets, currentIndex: selection.id)
            }
        }
    }

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(0..<photoLibrary.assets.count, id: \.self) { index in
                    ThumbnailCell(asset: photoLibrary.assets.object(at: index))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedPhoto = PhotoSelection(id: index)
                        }
                }
            }
        }
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
        .overlay(alignment: .bottomLeading) {
            HStack(spacing: 3) {
                if let record = BackupBadge.record(for: asset.localIdentifier), let fc = record.faceCount, fc > 0 {
                    Label("\(fc)", systemImage: "face.smiling")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.black.opacity(0.55), in: Capsule())
                }
                if asset.mediaType == .video {
                    Image(systemName: "video.fill")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .padding(4)
                }
            }
            .padding(4)
        }
        .overlay(alignment: .bottomTrailing) {
            BackupCloudBadge(assetId: asset.localIdentifier)
                .padding(4)
        }
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
            if let result {
                DispatchQueue.main.async { thumbnail = result }
            }
        }
    }
}
