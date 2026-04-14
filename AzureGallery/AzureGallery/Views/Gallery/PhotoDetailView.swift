import SwiftUI
import Photos
import MapKit

struct PhotoDetailView: View {
    let fetchResult: PHFetchResult<PHAsset>
    @State var currentIndex: Int
    @Environment(\.dismiss) private var dismiss

    @State private var showMetadata = false

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

            // Back button — top layer so it always receives taps
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
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
                        .padding(.trailing, 16)
                        .padding(.top, 8)
                }
                Spacer()

                // Swipe-up hint
                if !showMetadata {
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 36, height: 4)
                        Text("Swipe up for details")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .allowsHitTesting(false)
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { v in
                    let h = v.translation.height
                    let w = v.translation.width
                    if h < -60 { showMetadata = true }
                    if h > 80  { dismiss() }
                    // swipe right from leading edge only
                    if w > 100 && abs(w) > abs(h) * 2 { dismiss() }
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

// MARK: - Zoomable image

private struct ZoomableImageView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.clear

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(magnifyGesture())
                    .gesture(panGesture())
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = scale > 1 ? 1 : 2
                            offset = .zero
                        }
                    }
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
            }
        }
        .task(id: asset.localIdentifier) {
            await loadImage()
        }
    }

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

    private func loadImage() async {
        image = nil
        scale = 1
        offset = .zero
        lastScale = 1

        // Fast low-res pass first so something appears immediately
        if let thumb = await fetchImage(size: CGSize(width: 600, height: 600), mode: .fastFormat) {
            image = thumb
        }
        guard !Task.isCancelled else { return }

        // Full-resolution pass
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
}

// MARK: - Metadata sheet

private struct MetadataSheet: View {
    let asset: PHAsset
    @State private var record: BackupRecord?
    @State private var fileSize: Int64?
    @State private var location: CLPlacemark?

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
                        if let fc = rec.faceCount, fc > 0 {
                            LabeledRow(label: "Faces", value: "\(fc)")
                        }
                        if !rec.sceneLabelsArray.isEmpty {
                            LabeledRow(label: "Scene", value: rec.sceneLabelsArray.prefix(3).joined(separator: ", "))
                        }
                        if rec.hasText {
                            LabeledRow(label: "Contains Text", value: "Yes")
                        }
                        if rec.faceCount == nil && rec.sceneLabelsArray.isEmpty && !rec.hasText {
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
