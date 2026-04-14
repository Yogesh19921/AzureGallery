import Foundation
import Photos
import Observation

private let backgroundSessionIdentifier = "com.yogesh.AzureGallery.backgroundUpload"
private let maxConcurrentUploads = 3
private let maxRetries = 3
/// UserDefaults key: maps URLSession taskIdentifier (String) → assetId (String).
/// Persisted so the mapping survives app termination between upload and delegate callback.
private let taskMapKey = "BackupEngine.taskMap"

/// Coordinates the full backup lifecycle: scanning the photo library, queuing new assets,
/// and uploading them to Azure Blob Storage via a background URLSession.
///
/// ## Background Uploads
/// Uses `URLSessionConfiguration.background` so uploads continue in `nsurlsessiond`
/// even when the app is suspended or killed. The `taskMap` persists `taskIdentifier → assetId`
/// across launches so delegate callbacks can update the correct database record.
///
/// ## Singleton
/// Must remain a singleton. iOS delivers background session events to the same session
/// identifier — creating a second session with the same ID produces undefined behaviour.
@Observable
final class BackupEngine: NSObject {
    static let shared = BackupEngine()

    private(set) var isRunning = false
    private(set) var activeUploads: Int = 0

    private var session: URLSession!
    private var backgroundCompletionHandler: (() -> Void)?
    private let db = DatabaseService.shared

    /// Persisted map: `"\(taskIdentifier)"` → `assetId`. Survives app termination.
    private var taskMap: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: taskMapKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: taskMapKey) }
    }

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: backgroundSessionIdentifier)
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Called from `AzureGalleryApp` when iOS re-launches the app to deliver background session events.
    func handleBackgroundSessionEvents(completionHandler: @escaping () -> Void) {
        backgroundCompletionHandler = completionHandler
    }

    // MARK: - Start

    /// Start the backup engine. Idempotent — repeated calls after the first are no-ops.
    ///
    /// 1. Resets any records stuck in `uploading` from the previous run.
    /// 2. Scans the library and queues new assets not yet in the database.
    /// 3. Registers a change observer for real-time detection of new photos.
    /// 4. Begins uploading pending records.
    func start(photoLibrary: PhotoLibraryService) async {
        guard !isRunning else { return }
        isRunning = true

        // Reset any records stuck in 'uploading' from a previous run
        try? db.resetStaleUploading()

        // Scan library and queue new photos
        await scanAndQueue(photoLibrary: photoLibrary)

        // Wire up real-time new photo detection
        photoLibrary.onNewAssets = { [weak self] newAssets in
            Task { await self?.queue(assets: newAssets) }
        }

        // Start processing
        await processQueue()
    }

    // MARK: - Scanning

    private func scanAndQueue(photoLibrary: PhotoLibraryService) async {
        // Queue photos regardless of whether Azure is configured.
        // Credentials are only required at upload time (processQueue).
        // This ensures gallery badges appear as soon as photos are known to the app.
        let knownIds = (try? db.allAssetIds()) ?? []
        let allowedIds = BackupSelectionService.shared.allowedAssetIds()  // nil = all
        var toQueue: [PHAsset] = []

        photoLibrary.assets.enumerateObjects { asset, _, _ in
            guard !knownIds.contains(asset.localIdentifier) else { return }
            guard allowedIds == nil || allowedIds!.contains(asset.localIdentifier) else { return }
            toQueue.append(asset)
        }

        await queue(assets: toQueue)
    }

    private func queue(assets: [PHAsset]) async {
        let allowedIds = BackupSelectionService.shared.allowedAssetIds()
        for asset in assets {
            guard allowedIds == nil || allowedIds!.contains(asset.localIdentifier) else { continue }
            guard (try? db.record(for: asset.localIdentifier)) == nil else { continue }
            let blobName = BlobNaming.blobName(for: asset)
            var record = BackupRecord(
                assetId: asset.localIdentifier,
                blobName: blobName,
                mediaType: asset.mediaType == .video ? "video" : "image",
                creationDate: asset.creationDate.map { ISO8601DateFormatter().string(from: $0) }
            )
            try? db.upsert(&record)
        }
    }

    // MARK: - Processing

    func processQueue() async {
        guard let config = loadConfig() else { return }
        let blobService = AzureBlobService(config: config)

        let pending: [BackupRecord]
        do {
            pending = try db.pendingRecords(limit: maxConcurrentUploads * 2)
        } catch {
            return
        }

        for record in pending {
            guard activeUploads < maxConcurrentUploads else { break }
            await uploadRecord(record, blobService: blobService)
        }
    }

    private func uploadRecord(_ record: BackupRecord, blobService: AzureBlobService) async {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [record.assetId], options: nil).firstObject else {
            try? db.markPermFailed(assetId: record.assetId, error: "Asset no longer in library")
            return
        }

        try? db.updateStatus(assetId: record.assetId, status: .uploading)

        // Vision analysis before upload — non-blocking, best-effort
        let analysis = await VisionService.shared.analyze(asset: asset)
        try? db.updateVisionMetadata(
            assetId: record.assetId,
            faceCount: analysis.faceCount > 0 ? analysis.faceCount : nil,
            sceneLabels: analysis.sceneLabels.map(\.label),
            hasText: !analysis.recognizedText.isEmpty
        )

        do {
            let tempURL = try await FileExporter.export(asset: asset)
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int64) ?? 0
            let contentType = contentType(for: asset)

            // Register in manifest with Vision metadata
            ManifestManager.shared.addEntry(
                blobName: record.blobName,
                asset: asset,
                analysis: analysis,
                fileSize: fileSize
            )
            var uploadRequest = try blobService.uploadRequest(
                blobName: record.blobName,
                contentType: contentType,
                fileSize: fileSize
            )
            uploadRequest.setValue(tempURL.lastPathComponent, forHTTPHeaderField: "x-ms-client-request-id")

            let task = session.uploadTask(with: uploadRequest, fromFile: tempURL)
            var map = taskMap
            map[String(task.taskIdentifier)] = record.assetId
            taskMap = map
            activeUploads += 1
            task.resume()
        } catch {
            try? db.updateStatus(assetId: record.assetId, status: .failed, error: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func loadConfig() -> AzureConfig? {
        guard let cs = KeychainHelper.load(key: KeychainHelper.connectionStringKey),
              let container = KeychainHelper.load(key: KeychainHelper.containerNameKey) else { return nil }
        return try? AzureConfig.parse(connectionString: cs, containerName: container)
    }

    private func contentType(for asset: PHAsset) -> String {
        asset.mediaType == .video ? "video/quicktime" : "image/heic"
    }
}

// MARK: - URLSession Delegate

extension BackupEngine: URLSessionDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let key = String(task.taskIdentifier)
        var map = taskMap
        guard let assetId = map[key] else { return }
        map.removeValue(forKey: key)
        taskMap = map

        DispatchQueue.main.async { self.activeUploads = max(0, self.activeUploads - 1) }

        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0

        if let error {
            handleUploadFailure(assetId: assetId, error: error.localizedDescription)
        } else if statusCode == 201 || statusCode == 200 {
            try? db.updateStatus(assetId: assetId, status: .uploaded)
            // Refresh gallery badges for the newly-uploaded photo.
            DispatchQueue.main.async { BackupBadge.invalidate() }
            // Delete temp file
            if let fileURL = (task as? URLSessionUploadTask).flatMap({ _ in nil as URL? }) {
                try? FileManager.default.removeItem(at: fileURL)
            }
        } else {
            handleUploadFailure(assetId: assetId, error: "HTTP \(statusCode)")
        }

        // Process more from queue
        Task { await processQueue() }
    }

    private func handleUploadFailure(assetId: String, error: String) {
        guard let record = try? db.record(for: assetId) else { return }
        if record.retries >= maxRetries - 1 {
            try? db.markPermFailed(assetId: assetId, error: error)
        } else {
            try? db.incrementRetry(assetId: assetId)
            try? db.updateStatus(assetId: assetId, status: .failed, error: error)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
