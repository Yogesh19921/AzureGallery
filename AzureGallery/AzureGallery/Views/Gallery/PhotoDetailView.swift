import SwiftUI
import Photos
import MapKit
import AVKit

struct PhotoDetailView: View {
    let fetchResult: PHFetchResult<PHAsset>
    @State var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    @State private var showMetadata = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Paging viewer
            TabView(selection: $currentIndex) {
                ForEach(0..<fetchResult.count, id: \.self) { index in
                    ZoomableImageView(asset: fetchResult.object(at: index))
                        .tag(index)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .offset(y: dragOffset)
            .opacity(1 - min(0.5, abs(dragOffset) / 400))

            // Top bar
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.title3.weight(.semibold))
                            Text("Back")
                                .font(.body)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.5), in: Capsule())
                    }
                    .padding(.leading, 16)
                    .padding(.top, 8)

                    Spacer()

                    Text("\(currentIndex + 1) / \(fetchResult.count)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.top, 8)

                    // Info button — always available, no gesture needed
                    Button { showMetadata = true } label: {
                        Image(systemName: "info.circle")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.black.opacity(0.5), in: Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                Spacer()
            }
        }
        // simultaneousGesture so TabView paging (horizontal) still works.
        // Only respond to clearly vertical drags.
        .simultaneousGesture(
            DragGesture(minimumDistance: 50)
                .onChanged { v in
                    let h = v.translation.height
                    let w = v.translation.width
                    guard abs(h) > abs(w) * 1.5 else { return }
                    dragOffset = h
                }
                .onEnded { v in
                    let h = v.translation.height
                    let w = v.translation.width
                    let isVertical = abs(h) > abs(w) * 1.5
                    if isVertical && h > 120 {
                        dismiss()
                    } else if isVertical && h < -80 {
                        showMetadata = true
                    }
                    withAnimation(.spring(duration: 0.25)) { dragOffset = 0 }
                }
        )
        .sheet(isPresented: $showMetadata) {
            MetadataSheet(asset: fetchResult.object(at: currentIndex))
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(.ultraThinMaterial)
        }
        .statusBarHidden()
    }
}

// MARK: - Zoomable image / video player

private struct ZoomableImageView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1

    // Video
    @State private var player: AVPlayer?
    @State private var isPlayingVideo = false
    @State private var loadingVideo = false

    private var isVideo: Bool { asset.mediaType == .video }

    var body: some View {
        ZStack {
            Color.clear

            if isPlayingVideo, let player {
                VideoPlayer(player: player)
                    .onDisappear {
                        player.pause()
                        self.player = nil
                        self.isPlayingVideo = false
                    }
            } else if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnifyGesture())
                    // Pan only when zoomed — at 1x, TabView handles left/right swipes
                    .highPriorityGesture(scale > 1 ? panGesture() : nil)
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = scale > 1 ? 1 : 2
                            offset = .zero
                        }
                    }
                    .overlay {
                        if isVideo {
                            // Play button overlay for videos
                            Button {
                                Task { await playVideo() }
                            } label: {
                                if loadingVideo {
                                    ProgressView()
                                        .controlSize(.large)
                                        .tint(.white)
                                } else {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 64))
                                        .foregroundStyle(.white.opacity(0.9))
                                        .shadow(radius: 10)
                                }
                            }
                            .disabled(loadingVideo)
                        }
                    }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .task(id: asset.localIdentifier) {
            resetState()
            await loadImage()
        }
    }

    private func resetState() {
        image = nil
        scale = 1
        offset = .zero
        lastScale = 1
        player?.pause()
        player = nil
        isPlayingVideo = false
        loadingVideo = false
    }

    // MARK: - Gestures

    private func magnifyGesture() -> some Gesture {
        MagnifyGesture()
            .onChanged { v in scale = max(1, lastScale * v.magnification) }
            .onEnded { v in
                lastScale = scale
                if scale < 1 { withAnimation { scale = 1; offset = .zero }; lastScale = 1 }
            }
    }

    private func panGesture() -> some Gesture {
        DragGesture()
            .onChanged { v in if scale > 1 { offset = v.translation } }
            .onEnded { _ in
                if scale <= 1 { withAnimation { offset = .zero } }
            }
    }

    // MARK: - Image loading

    private func loadImage() async {
        if let thumb = await fetchImage(size: CGSize(width: 600, height: 600), mode: .fastFormat) {
            image = thumb
        }
        guard !Task.isCancelled, !isVideo else { return }
        if let full = await fetchImage(size: PHImageManagerMaximumSize, mode: .highQualityFormat) {
            image = full
        }
    }

    private func fetchImage(size: CGSize, mode: PHImageRequestOptionsDeliveryMode) async -> UIImage? {
        let capturedAsset = asset
        return await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = mode
            options.isNetworkAccessAllowed = true
            options.isSynchronous = false
            DispatchQueue.global(qos: .userInitiated).async {
                PHImageManager.default().requestImage(
                    for: capturedAsset,
                    targetSize: size,
                    contentMode: .aspectFit,
                    options: options
                ) { result, _ in
                    continuation.resume(returning: result)
                }
            }
        }
    }

    // MARK: - Video playback

    private func playVideo() async {
        loadingVideo = true
        let capturedAsset = asset
        let avAsset: AVAsset? = await withCheckedContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .automatic
            PHImageManager.default().requestAVAsset(
                forVideo: capturedAsset, options: options
            ) { avAsset, _, _ in
                continuation.resume(returning: avAsset)
            }
        }
        loadingVideo = false
        guard let avAsset else { return }
        let newPlayer = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
        player = newPlayer
        isPlayingVideo = true
        newPlayer.play()
    }
}

// MARK: - Metadata sheet

private struct MetadataSheet: View {
    let asset: PHAsset
    @State private var record: BackupRecord?
    @State private var fileSize: Int64?
    @State private var location: CLPlacemark?
    @State private var downloading = false
    @State private var downloadResult: DownloadResult?

    enum DownloadResult {
        case success, error(String)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ThumbnailHeader(asset: asset)
                        .listRowBackground(Color.clear)
                        .listRowInsets(.init())
                }

                Section("Info") {
                    if let date = asset.creationDate {
                        LabeledRow(label: "Date", value: date.formatted(date: .long, time: .shortened))
                    }
                    LabeledRow(label: "Dimensions", value: "\(asset.pixelWidth) × \(asset.pixelHeight)")
                    if let size = fileSize {
                        LabeledRow(label: "File Size", value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    }
                    LabeledRow(label: "Type", value: asset.mediaType == .video ? "Video" : "Photo")
                    if asset.isFavorite {
                        LabeledRow(label: "Favorite", value: "Yes")
                    }
                }

                if let place = location {
                    Section("Location") {
                        LabeledRow(label: "Place", value: [place.locality, place.administrativeArea, place.country]
                            .compactMap { $0 }.joined(separator: ", "))
                        if let coord = asset.location?.coordinate {
                            Map(position: .constant(.region(
                                MKCoordinateRegion(
                                    center: coord,
                                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                )
                            ))) {
                                Marker("", coordinate: coord)
                            }
                            .frame(height: 160)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }

                if let rec = record {
                    Section("AI Analysis") {
                        if let caption = rec.caption {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("AI Description", systemImage: "sparkles")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.blue)
                                Text(caption)
                                    .font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                        if let fc = rec.faceCount, fc > 0 {
                            LabeledRow(label: "Faces", value: "\(fc)")
                        }
                        if !rec.sceneLabelsArray.isEmpty {
                            LabeledRow(label: "Scene", value: rec.sceneLabelsArray.prefix(3).joined(separator: ", "))
                        }
                        if rec.hasText {
                            LabeledRow(label: "Contains Text", value: "Yes")
                        }
                        if rec.faceCount == nil && rec.sceneLabelsArray.isEmpty && !rec.hasText && rec.caption == nil {
                            Text("Not yet analysed — will run before backup")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Backup") {
                    if let rec = record {
                        LabeledRow(label: "Status", value: rec.status.displayName)
                        if let uploaded = rec.uploadedAt {
                            LabeledRow(label: "Backed Up", value: uploaded)
                        }
                        if let err = rec.error {
                            LabeledRow(label: "Error", value: err)
                        }
                        if rec.status == .uploaded {
                            Button {
                                Task { await downloadFromCloud(record: rec) }
                            } label: {
                                HStack {
                                    if downloading {
                                        ProgressView().controlSize(.small)
                                        Text("Downloading…")
                                    } else {
                                        Image(systemName: "icloud.and.arrow.down")
                                        Text("Download from Cloud")
                                    }
                                }
                            }
                            .disabled(downloading)

                            if let result = downloadResult {
                                switch result {
                                case .success:
                                    Label("Saved to Photos", systemImage: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                        .font(.caption)
                                case .error(let msg):
                                    Label(msg, systemImage: "exclamation.triangle.fill")
                                        .foregroundStyle(.red)
                                        .font(.caption)
                                }
                            }
                        }
                    } else {
                        LabeledRow(label: "Status", value: "Not queued")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            record = BackupBadge.record(for: asset.localIdentifier)

            let resources = PHAssetResource.assetResources(for: asset)
            if let resource = resources.first,
               let size = resource.value(forKey: "fileSize") as? Int64 {
                fileSize = size
            }

            if let loc = asset.location {
                location = try? await CLGeocoder().reverseGeocodeLocation(loc).first
            }
        }
    }

    // MARK: - Cloud download

    private func downloadFromCloud(record: BackupRecord) async {
        downloading = true
        downloadResult = nil
        defer { downloading = false }

        guard let provider = CloudStorageFactory.makeProvider() else {
            downloadResult = .error("Cloud storage not configured")
            return
        }

        do {
            let data = try await provider.downloadBlob(blobName: record.blobName)
            try await saveToPhotos(data: data, mediaType: record.mediaType)
            downloadResult = .success
        } catch {
            downloadResult = .error(error.localizedDescription)
        }
    }

    private func saveToPhotos(data: Data, mediaType: String) async throws {
        if mediaType == "video" {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".MOV")
            try data.write(to: tempURL)
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: tempURL, options: nil)
            }
            try? FileManager.default.removeItem(at: tempURL)
        } else {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        }
    }
}

private struct ThumbnailHeader: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipped()
            }
        }
        .task {
            image = await withCheckedContinuation { continuation in
                let options = PHImageRequestOptions()
                options.deliveryMode = .fastFormat  // single callback — safe with continuation
                options.isNetworkAccessAllowed = true
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: CGSize(width: 800, height: 600),
                    contentMode: .aspectFill,
                    options: options
                ) { img, _ in continuation.resume(returning: img) }
            }
        }
    }
}

private struct LabeledRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}

private extension BackupStatus {
    var displayName: String {
        switch self {
        case .pending:    return "Pending"
        case .uploading:  return "Uploading…"
        case .uploaded:   return "Backed up ✓"
        case .failed:     return "Failed"
        case .permFailed: return "Failed (permanent)"
        }
    }
}
