import SwiftUI
import Photos

/// Groups uploaded backup records by month and lets the user download them
/// from Azure — either individually or an entire month at once.
struct RestoreView: View {
    @State private var months: [MonthGroup] = []
    @State private var localIds: Set<String> = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView("Scanning…")
            } else if months.isEmpty {
                ContentUnavailableView(
                    "Nothing to Restore",
                    systemImage: "icloud.slash",
                    description: Text("No backed-up files are missing from this device.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(months) { month in
                            VStack(alignment: .leading, spacing: 8) {
                                // Month header
                                HStack {
                                    Text(month.title).font(.headline)
                                    Spacer()
                                    Text("\(month.records.count) files")
                                        .font(.caption).foregroundStyle(.secondary)
                                    DownloadMonthButton(month: month)
                                }
                                .padding(.horizontal)

                                // Thumbnail grid
                                let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(month.records) { rec in
                                        RestoreThumbnail(record: rec)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
        }
        .navigationTitle("Restore from Cloud")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }

        // Uploaded records from DB
        let uploaded = (try? DatabaseService.shared.uploadedRecords()) ?? []
        guard !uploaded.isEmpty else { months = []; return }

        // Which of those still exist on the device?
        let assetIds = uploaded.map(\.assetId)
        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assetIds, options: nil)
        var onDevice = Set<String>()
        fetched.enumerateObjects { asset, _, _ in
            onDevice.insert(asset.localIdentifier)
        }
        localIds = onDevice

        // Filter to cloud-only (not on device)
        let cloudOnly = uploaded.filter { !onDevice.contains($0.assetId) }
        guard !cloudOnly.isEmpty else { months = []; return }

        // Group by YYYY-MM
        let grouped = Dictionary(grouping: cloudOnly) { rec -> String in
            guard let dateStr = rec.creationDate,
                  let date = ISO8601DateFormatter().date(from: dateStr) else {
                return "Unknown"
            }
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM"
            return fmt.string(from: date)
        }

        let fmt = DateFormatter()
        months = grouped.keys.sorted().reversed().map { key -> MonthGroup in
            // Parse YYYY-MM into a nice title like "April 2026"
            fmt.dateFormat = "yyyy-MM"
            let title: String
            if let d = fmt.date(from: key) {
                fmt.dateFormat = "MMMM yyyy"
                title = fmt.string(from: d)
            } else {
                title = key
            }
            return MonthGroup(id: key, title: title, records: grouped[key] ?? [])
        }
    }
}

// MARK: - Data types

struct MonthGroup: Identifiable {
    let id: String        // "2026-04"
    let title: String     // "April 2026"
    let records: [BackupRecord]
}

// MARK: - Thumbnail cell with cloud preview

private struct RestoreThumbnail: View {
    let record: BackupRecord
    @State private var thumbnail: UIImage?
    @State private var downloading = false
    @State private var done = false

    private var cellSize: CGFloat { (UIScreen.main.bounds.width - 4) / 3 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let img = thumbnail {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: cellSize, height: cellSize)
                    .clipped()
            } else if record.mediaType == "video" {
                // Videos can't produce a thumbnail from first 64KB
                ZStack {
                    Rectangle().fill(Color(.systemGray5))
                    Image(systemName: "video.fill").font(.title2).foregroundStyle(.secondary)
                }
                .frame(width: cellSize, height: cellSize)
            } else {
                ZStack {
                    Rectangle().fill(Color(.systemGray5))
                    ProgressView().controlSize(.small)
                }
                .frame(width: cellSize, height: cellSize)
            }

            // Download button overlay
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .padding(4)
            } else {
                Button {
                    Task { await download() }
                } label: {
                    Image(systemName: downloading ? "ellipsis.circle" : "icloud.and.arrow.down")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.55), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(downloading)
                .padding(4)
            }
        }
        .task(id: record.id) {
            guard record.mediaType != "video" else { return }
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        guard let cs = KeychainHelper.load(key: KeychainHelper.connectionStringKey),
              let container = KeychainHelper.load(key: KeychainHelper.containerNameKey),
              let config = try? AzureConfig.parse(connectionString: cs, containerName: container) else { return }
        let blob = AzureBlobService(config: config)
        guard let data = try? await blob.downloadBlobRange(blobName: record.blobName, offset: 0, length: 65536),
              let img = UIImage(data: data) else { return }
        thumbnail = img
    }

    private func download() async {
        downloading = true
        defer { downloading = false }
        do {
            let data = try await downloadBlob(blobName: record.blobName)
            try await saveToPhotos(data: data, mediaType: record.mediaType)
            done = true
        } catch {}
    }
}

// MARK: - Download entire month

private struct DownloadMonthButton: View {
    let month: MonthGroup
    @State private var downloading = false
    @State private var completed = 0
    @State private var failed = 0

    var body: some View {
        Button {
            Task { await downloadAll() }
        } label: {
            if downloading {
                HStack(spacing: 4) {
                    ProgressView().controlSize(.mini)
                    Text("\(completed)/\(month.records.count)")
                        .font(.caption2).monospacedDigit()
                }
            } else if completed == month.records.count && completed > 0 {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("Download All")
                    .font(.caption.weight(.medium))
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .disabled(downloading)
    }

    private func downloadAll() async {
        downloading = true
        completed = 0
        failed = 0
        for record in month.records {
            do {
                let data = try await downloadBlob(blobName: record.blobName)
                try await saveToPhotos(data: data, mediaType: record.mediaType)
                completed += 1
            } catch {
                failed += 1
                completed += 1
            }
        }
        downloading = false
    }
}

// MARK: - Shared download helpers

private func downloadBlob(blobName: String) async throws -> Data {
    guard let cs = KeychainHelper.load(key: KeychainHelper.connectionStringKey),
          let container = KeychainHelper.load(key: KeychainHelper.containerNameKey),
          let config = try? AzureConfig.parse(connectionString: cs, containerName: container) else {
        throw RestoreError.notConfigured
    }
    return try await AzureBlobService(config: config).downloadBlob(blobName: blobName)
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

private enum RestoreError: LocalizedError {
    case notConfigured
    var errorDescription: String? { "Azure not configured" }
}
