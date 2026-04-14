import SwiftUI
import Photos

struct SearchView: View {
    @State private var query = ""
    @State private var results: [BackupRecord] = []
    @State private var activeFilter: QuickFilter?

    enum QuickFilter: String, CaseIterable {
        case hasText     = "Has Text"
        case selfie      = "Selfie"
        case group       = "Group (3+)"
        case outdoor     = "Outdoor"
        case indoor      = "Indoor"
        case landscape   = "Landscape"
        case animal      = "Animal"
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Scene, faces, text…")
            .onSubmit(of: .search) { search() }
            .onChange(of: query) { _, newVal in
                if newVal.isEmpty && activeFilter == nil { results = [] }
            }
        }
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

        // Semantic search: expand free-text query into matching scene labels via NLEmbedding
        if !query.isEmpty && sceneKw == nil {
            var merged: [String: BackupRecord] = [:]

            // 1. Direct keyword match against all searchable columns (raw query)
            let direct = (try? DatabaseService.shared.searchRecords(
                hasText: hasText, minFaces: minFaces, sceneKeyword: query
            )) ?? []
            for r in direct { merged[r.assetId] = r }

            // 2. Semantic expansion — find related labels via NLEmbedding
            let expanded = SemanticSearchService.expandQuery(query)
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
                    .frame(width: cellSize, height: cellSize)
                    .clipped()
            } else {
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: cellSize, height: cellSize)
            }
            BackupCloudBadge(assetId: record.assetId)
                .padding(4)
        }
        .task(id: record.assetId) {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [record.assetId], options: nil)
            guard let asset = assets.firstObject else { return }
            let size = CGSize(width: cellSize * 2, height: cellSize * 2)
            image = await withCheckedContinuation { cont in
                let opts = PHImageRequestOptions()
                opts.deliveryMode = .fastFormat
                opts.isNetworkAccessAllowed = true
                PHImageManager.default().requestImage(
                    for: asset, targetSize: size, contentMode: .aspectFill, options: opts
                ) { img, _ in cont.resume(returning: img) }
            }
        }
    }
}
