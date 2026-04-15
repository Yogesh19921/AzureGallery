import SwiftUI
import Photos
import Combine

// Identifiable wrapper so we can use fullScreenCover(item:)
private struct PhotoSelection: Identifiable {
    let id: Int // index into fetchResult
}

struct GalleryView: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var selectedPhoto: PhotoSelection?
    @State private var activeUploads = 0
    @State private var pendingCount = 0
    @State private var visibleMonth = ""

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
            .toolbarTitleDisplayMode(.inlineLarge)
            .fullScreenCover(item: $selectedPhoto) { selection in
                PhotoDetailView(fetchResult: photoLibrary.assets, currentIndex: selection.id)
            }
            .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
                activeUploads = BackupEngine.shared.activeUploads
                pendingCount = (try? DatabaseService.shared.pendingCount()) ?? 0
            }
        }
    }

    private var photoGrid: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    // Backup progress banner
                    if activeUploads > 0 || pendingCount > 0 {
                        HStack(spacing: 8) {
                            if activeUploads > 0 {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "cloud.fill").foregroundStyle(.blue)
                            }
                            Text(activeUploads > 0
                                 ? "Backing up… \(pendingCount) remaining"
                                 : "\(pendingCount) pending")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                    }

                    // Photo grid grouped by month
                    let sections = buildSections()
                    ForEach(sections, id: \.title) { section in
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(section.indices, id: \.self) { index in
                                let asset = photoLibrary.assets.object(at: index)
                                ThumbnailCell(asset: asset)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        selectedPhoto = PhotoSelection(id: index)
                                    }
                                    .contextMenu {
                                        let status = BackupBadge.record(for: asset.localIdentifier)?.status
                                        Label(status == .uploaded ? "Backed Up" : status == .pending ? "Pending Upload" : "Not Backed Up",
                                              systemImage: status == .uploaded ? "checkmark.icloud.fill" : "icloud")

                                        Button {
                                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                            asset.toggleFavorite()
                                        } label: {
                                            Label(asset.isFavorite ? "Unfavorite" : "Favorite",
                                                  systemImage: asset.isFavorite ? "heart.slash" : "heart")
                                        }

                                        ShareLink(item: asset.localIdentifier) {
                                            Label("Share", systemImage: "square.and.arrow.up")
                                        }
                                    }
                                    .onAppear {
                                        // Track which month is currently visible
                                        visibleMonth = section.title
                                    }
                            }
                        }
                    }
                }
            }
            .refreshable {
                await photoLibrary.requestAuthorization()
                await BackupEngine.shared.resyncSelection()
            }

            // Floating date overlay — large bold, no background
            if !visibleMonth.isEmpty {
                Text(visibleMonth)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary.opacity(0.7))
                    .padding(.leading, 16)
                    .padding(.top, 6)
                    .allowsHitTesting(false)
                    .animation(.easeInOut(duration: 0.15), value: visibleMonth)
            }
        }
    }

    // MARK: - Group photos by month

    private struct MonthSection {
        let title: String     // "April 2026"
        let indices: [Int]    // indices into fetchResult
    }

    private func buildSections() -> [MonthSection] {
        let count = photoLibrary.assets.count
        guard count > 0 else { return [] }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"

        var sections: [MonthSection] = []
        var currentTitle = ""
        var currentIndices: [Int] = []

        for i in 0..<count {
            let asset = photoLibrary.assets.object(at: i)
            let title = asset.creationDate.map { formatter.string(from: $0) } ?? "Unknown"

            if title != currentTitle {
                if !currentIndices.isEmpty {
                    sections.append(MonthSection(title: currentTitle, indices: currentIndices))
                }
                currentTitle = title
                currentIndices = [i]
            } else {
                currentIndices.append(i)
            }
        }
        if !currentIndices.isEmpty {
            sections.append(MonthSection(title: currentTitle, indices: currentIndices))
        }
        return sections
    }
}

// MARK: - Thumbnail cell

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

// MARK: - PHAsset helpers

private extension PHAsset {
    func toggleFavorite() {
        PHPhotoLibrary.shared().performChanges {
            let request = PHAssetChangeRequest(for: self)
            request.isFavorite = !self.isFavorite
        }
    }
}
