import SwiftUI
import Photos

private struct SearchSelection: Identifiable {
    let id: String
    let fetchResult: PHFetchResult<PHAsset>
    let index: Int
}

struct SearchView: View {
    @State private var query = ""
    @State private var results: [BackupRecord] = []
    @State private var activeFilter: QuickFilter?
    @State private var selectedPhoto: SearchSelection?

    enum QuickFilter: String, CaseIterable {
        case hasText     = "Has Text"
        case selfie      = "Selfie"
        case group       = "Group (3+)"
        case outdoor     = "Outdoor"
        case indoor      = "Indoor"
        case landscape   = "Landscape"
        case animal      = "Animal"
    }

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 2)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar — full width tappable
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search photos…", text: $query)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { search() }
                    if !query.isEmpty {
                        Button { query = ""; results = [] } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(12)
                .contentShape(Rectangle())
                .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 8)

                // Quick filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(QuickFilter.allCases, id: \.self) { filter in
                            Button {
                                if activeFilter == filter { activeFilter = nil } else { activeFilter = filter }
                                search()
                            } label: {
                                Text(filter.rawValue)
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(activeFilter == filter ? Color.blue : Color(.systemGray5),
                                                in: Capsule())
                                    .foregroundStyle(activeFilter == filter ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                if results.isEmpty {
                    ContentUnavailableView.search
                        .frame(maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(results) { record in
                                SearchThumbnail(record: record)
                                    .contentShape(Rectangle())
                                    .onTapGesture { openPhoto(record) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .fullScreenCover(item: $selectedPhoto) { selection in
                PhotoDetailView(fetchResult: selection.fetchResult, currentIndex: selection.index)
            }
        }
    }

    private func openPhoto(_ record: BackupRecord) {
        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [record.assetId], options: nil)
        guard fetchResult.count > 0 else { return }
        selectedPhoto = SearchSelection(id: record.assetId, fetchResult: fetchResult, index: 0)
    }

    private func search() {
        let hasText: Bool? = activeFilter == .hasText ? true : nil
        let minFaces: Int?
        switch activeFilter {
        case .selfie: minFaces = 1
        case .group:  minFaces = 3
        default:      minFaces = nil
        }

        var sceneKw: String? = nil
        switch activeFilter {
        case .outdoor:   sceneKw = "outdoor"
        case .indoor:    sceneKw = "indoor"
        case .landscape: sceneKw = "landscape"
        case .animal:    sceneKw = "animal"
        default: break
        }

        if !query.isEmpty && sceneKw == nil {
            var merged: [String: BackupRecord] = [:]

            // 1. Direct match against sceneLabels + animalLabels + captions
            let direct = (try? DatabaseService.shared.searchRecords(
                hasText: hasText, minFaces: minFaces, sceneKeyword: query
            )) ?? []
            for r in direct { merged[r.assetId] = r }

            // 2. Semantic expansion — closely related labels
            let expanded = SemanticSearchService.expandQuery(query, topN: 3)
            for kw in expanded where kw != query.lowercased() {
                let partial = (try? DatabaseService.shared.searchRecords(
                    hasText: hasText, minFaces: minFaces, sceneKeyword: kw
                )) ?? []
                for r in partial { merged[r.assetId] = r }
            }

            // 3. OCR text search
            let textResults = (try? DatabaseService.shared.searchRecords(
                hasText: hasText, minFaces: minFaces, textQuery: query
            )) ?? []
            for r in textResults { merged[r.assetId] = r }

            results = Array(merged.values.prefix(200))
        } else {
            results = (try? DatabaseService.shared.searchRecords(
                hasText: hasText,
                minFaces: minFaces,
                sceneKeyword: sceneKw
            )) ?? []
        }
    }
}

// MARK: - Thumbnail cell for search results

private struct SearchThumbnail: View {
    let record: BackupRecord
    @State private var image: UIImage?

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 4) / 3 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
            }
        }
        .frame(width: cellSize, height: cellSize)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            BackupCloudBadge(assetId: record.assetId)
                .padding(4)
        }
        .task(id: record.assetId) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [record.assetId], options: nil)
            guard let asset = assets.firstObject else { return }
            let scale = UIScreen.main.scale
            let pixelSize = CGSize(width: cellSize * scale, height: cellSize * scale)
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat
            opts.resizeMode = .exact
            opts.isNetworkAccessAllowed = true
            image = await withCheckedContinuation { cont in
                PHImageManager.default().requestImage(
                    for: asset, targetSize: pixelSize, contentMode: .aspectFill, options: opts
                ) { img, _ in cont.resume(returning: img) }
            }
        }
    }
}
