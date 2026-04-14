import Foundation
import Photos
import Observation
import CryptoKit
import UIKit

private let backgroundSessionIdentifier = "com.yogesh.AzureGallery.backgroundUpload"
private let maxConcurrentUploads = 3
private let maxRetries = 3

/// Live progress snapshot for a single in-flight upload.
struct ActiveUploadItem: Identifiable {
    let id: String          // assetId — unique per asset
    let fileName: String    // last path component of blobName shown in the UI
    var bytesSent: Int64 = 0
    var totalBytes: Int64 = 0
    var progress: Double { totalBytes > 0 ? Double(bytesSent) / Double(totalBytes) : 0 }
}
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
    private(set) var isPaused = false
    private(set) var activeUploads: Int = 0
    /// Live per-file progress, keyed by assetId. Populated when a task starts, removed on completion.
    private(set) var activeUploadItems: [String: ActiveUploadItem] = [:]

    private var session: URLSession!
    private var backgroundCompletionHandler: (() -> Void)?
    private let db = DatabaseService.shared
    private weak var photoLibrary: PhotoLibraryService?

    /// Tracks how many uploads succeeded in the current batch (while activeUploads > 0).
    /// Reset to 0 when activeUploads drops to 0 and a notification is posted.
    private var batchUploadedCount = 0

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

    // MARK: - Pause / Resume

    /// Pause new uploads. In-flight background tasks are allowed to finish naturally.
    func pause() {
        guard !isPaused else { return }
        isPaused = true
        Task { await MainActor.run { AppLogger.shared.info("Backup paused", tag: "BackupEngine") } }
    }

    /// Resume uploads and immediately drain the pending queue.
    func resume() {
        guard isPaused else { return }
        isPaused = false
        Task {
            await MainActor.run { AppLogger.shared.info("Backup resumed", tag: "BackupEngine") }
            await processQueue()
        }
    }

    // MARK: - Selection Resync

    /// Called when the user changes backup sources. Purges queued records that no longer
    /// match the selection, then re-scans to pick up newly selected albums.
    func resyncSelection() async {
        let allowed = BackupSelectionService.shared.allowedAssetIds()
        try? db.purgeNonUploadedNotIn(allowedIds: allowed)
        await MainActor.run {
            let count = allowed.map { "\($0.count) assets in selection" } ?? "all photos"
            AppLogger.shared.info("Resynced selection: \(count)", tag: "BackupEngine")
        }
        BackupBadge.invalidate()
        if let lib = photoLibrary {
            await scanAndQueue(photoLibrary: lib)
        }
        await processQueue()
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
        self.photoLibrary = photoLibrary

        // Enable battery monitoring so we can check charging state
        await MainActor.run { UIDevice.current.isBatteryMonitoringEnabled = true }

        // Auto-resume when network changes (e.g. Wi-Fi reconnects)
        NetworkMonitor.shared.onPathChange = { [weak self] in
            Task { await self?.processQueue() }
        }

        // Auto-resume when device begins charging
        NotificationCenter.default.addObserver(
            forName: UIDevice.batteryStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { await self?.processQueue() }
        }

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
        guard !isPaused else { return }

        let wifiOnly = UserDefaults.standard.bool(forKey: "wifiOnly")
        let chargeOnly = UserDefaults.standard.bool(forKey: "chargeOnly")
        let isCellular = NetworkMonitor.shared.isCellular
        let isCharging = await MainActor.run {
            let state = UIDevice.current.batteryState
            return state == .charging || state == .full
        }

        if !BackupEngine.shouldAllowUpload(wifiOnly: wifiOnly, chargeOnly: chargeOnly,
                                             isCellular: isCellular, isCharging: isCharging) {
            if wifiOnly && isCellular {
                await MainActor.run {
                    AppLogger.shared.warn("Wi-Fi Only enabled but on cellular — upload skipped", tag: "BackupEngine")
                }
            }
            if chargeOnly && !isCharging {
                await MainActor.run {
                    AppLogger.shared.warn("Charge Only enabled but not charging — upload skipped", tag: "BackupEngine")
                }
            }
            return
        }

        guard let config = loadConfig() else {
            await MainActor.run {
                AppLogger.shared.warn("Azure not configured — upload skipped", tag: "BackupEngine")
            }
            return
        }
        let blobService = AzureBlobService(config: config)

        let pending: [BackupRecord]
        do {
            pending = try db.pendingRecords(limit: maxConcurrentUploads * 2)
        } catch {
            await MainActor.run {
                AppLogger.shared.error("Failed to fetch pending records: \(error)", tag: "BackupEngine")
            }
            return
        }

        await MainActor.run {
            AppLogger.shared.info("Queue: \(pending.count) pending, \(activeUploads) active", tag: "BackupEngine")
        }

        for record in pending {
            guard activeUploads < maxConcurrentUploads else { break }
            await uploadRecord(record, blobService: blobService)
        }
    }

    private func uploadRecord(_ record: BackupRecord, blobService: AzureBlobService) async {
        let shortId = String(record.assetId.prefix(8))
        let blobShort = URL(string: record.blobName)?.lastPathComponent ?? record.blobName

        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [record.assetId], options: nil).firstObject else {
            try? db.markPermFailed(assetId: record.assetId, error: "Asset no longer in library")
            await MainActor.run {
                AppLogger.shared.error("[\(shortId)] Asset not in library — marked perm_failed", tag: "BackupEngine")
            }
            return
        }

        try? db.updateStatus(assetId: record.assetId, status: .uploading)
        await MainActor.run {
            AppLogger.shared.info("[\(shortId)] Starting upload: \(blobShort)", tag: "BackupEngine")
        }

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
            await MainActor.run {
                AppLogger.shared.info("[\(shortId)] Exported \(blobShort) — \(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))", tag: "BackupEngine")
            }

            // Duplicate detection via content hash
            if let hash = try? sha256Hash(of: tempURL) {
                try? db.updateHash(assetId: record.assetId, hash: hash)
                if let existing = try? db.recordByHash(hash: hash),
                   existing.assetId != record.assetId,
                   existing.status == .uploaded {
                    // Duplicate — skip upload, mark as uploaded
                    try? db.updateStatus(assetId: record.assetId, status: .uploaded)
                    try? FileManager.default.removeItem(at: tempURL)
                    await MainActor.run {
                        AppLogger.shared.info("[\(shortId)] Duplicate of \(String(existing.assetId.prefix(8))) — skipped upload", tag: "BackupEngine")
                        BackupBadge.invalidate()
                    }
                    return
                }
            }

            // Conflict resolution: skip if blob already exists in Azure (e.g. reinstall)
            if (try? await blobService.blobExists(blobName: record.blobName)) == true {
                try? db.updateStatus(assetId: record.assetId, status: .uploaded)
                try? FileManager.default.removeItem(at: tempURL)
                await MainActor.run {
                    AppLogger.shared.info("[\(shortId)] Blob exists in Azure — skipped re-upload", tag: "BackupEngine")
                    BackupBadge.invalidate()
                }
                return
            }

            // Register in manifest with Vision metadata
            ManifestManager.shared.addEntry(
                blobName: record.blobName,
                asset: asset,
                analysis: analysis,
                fileSize: fileSize
            )
            let tier = UserDefaults.standard.string(forKey: "storageTier")
            let uploadRequest = try blobService.uploadRequest(
                blobName: record.blobName,
                contentType: contentType,
                fileSize: fileSize,
                accessTier: tier?.isEmpty == false ? tier : nil
            )
            await MainActor.run {
                let urlStr = uploadRequest.url?.absoluteString ?? "?"
                AppLogger.shared.info("[\(shortId)] PUT \(urlStr)", tag: "BackupEngine")
            }

            let task = session.uploadTask(with: uploadRequest, fromFile: tempURL)
            var map = taskMap
            map[String(task.taskIdentifier)] = record.assetId
            taskMap = map
            activeUploads += 1
            let fileName = URL(string: record.blobName)?.lastPathComponent ?? record.blobName
            activeUploadItems[record.assetId] = ActiveUploadItem(
                id: record.assetId, fileName: fileName, totalBytes: fileSize
            )
            task.resume()
        } catch {
            try? db.updateStatus(assetId: record.assetId, status: .failed, error: error.localizedDescription)
            await MainActor.run {
                AppLogger.shared.error("[\(shortId)] Upload setup failed: \(error.localizedDescription)", tag: "BackupEngine")
            }
        }
    }

    // MARK: - Upload Policy

    /// Pure function for testability. Returns `true` when uploads should proceed.
    static func shouldAllowUpload(wifiOnly: Bool, chargeOnly: Bool,
                                   isCellular: Bool, isCharging: Bool) -> Bool {
        if wifiOnly && isCellular { return false }
        if chargeOnly && !isCharging { return false }
        return true
    }

    // MARK: - Content Hash

    /// Computes a SHA-256 hash of the file at `url` using streaming 1 MB chunks.
    private func sha256Hash(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 1_048_576)
            guard !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Helpers

    private func loadConfig() -> AzureConfig? {
        guard let cs = KeychainHelper.load(key: KeychainHelper.connectionStringKey),
              let container = KeychainHelper.load(key: KeychainHelper.containerNameKey) else { return nil }
        do {
            return try AzureConfig.parse(connectionString: cs, containerName: container)
        } catch {
            DispatchQueue.main.async {
                AppLogger.shared.error("Azure config parse failed: \(error.localizedDescription)", tag: "BackupEngine")
            }
            return nil
        }
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
        let assetId = map[key]          // may be nil if task map was lost (reinstall etc.)
        map.removeValue(forKey: key)
        taskMap = map

        // Always decrement — even if assetId is unknown. Guarding before this was the
        // "stuck uploading" bug: counter would never reach 0 when taskMap lost an entry.
        DispatchQueue.main.async {
            self.activeUploads = max(0, self.activeUploads - 1)
            if let assetId { self.activeUploadItems.removeValue(forKey: assetId) }

            // When all in-flight uploads finish and we had successful ones, post a notification
            if self.activeUploads == 0 && self.batchUploadedCount > 0 {
                if UIApplication.shared.applicationState != .active {
                    NotificationService.postBatchComplete(uploadedCount: self.batchUploadedCount)
                }
                self.batchUploadedCount = 0
            }
        }

        guard let assetId else {
            Task { await processQueue() }
            return
        }

        let shortId = String(assetId.prefix(8))
        let statusCode = (task.response as? HTTPURLResponse)?.statusCode ?? 0

        if let error {
            DispatchQueue.main.async {
                AppLogger.shared.error("[\(shortId)] URLSession error: \(error.localizedDescription)", tag: "BackupEngine")
            }
            handleUploadFailure(assetId: assetId, error: error.localizedDescription)
        } else if statusCode == 201 || statusCode == 200 {
            // Record bandwidth before clearing the active upload item
            let totalBytes = activeUploadItems[assetId]?.totalBytes ?? 0
            if totalBytes > 0 {
                try? db.recordUpload(bytes: totalBytes, date: Date())
            }
            batchUploadedCount += 1
            DispatchQueue.main.async {
                AppLogger.shared.info("[\(shortId)] Upload succeeded (HTTP \(statusCode))", tag: "BackupEngine")
            }
            try? db.updateStatus(assetId: assetId, status: .uploaded)
            DispatchQueue.main.async { BackupBadge.invalidate() }
            if let fileURL = (task as? URLSessionUploadTask).flatMap({ _ in nil as URL? }) {
                try? FileManager.default.removeItem(at: fileURL)
            }

            // Update badge count with remaining pending uploads
            let pending = (try? db.pendingCount()) ?? 0
            NotificationService.updateBadge(count: pending)
        } else {
            DispatchQueue.main.async {
                let headers = (task.response as? HTTPURLResponse)?.allHeaderFields
                let reqId = headers?["x-ms-request-id"] as? String ?? "—"
                AppLogger.shared.error("[\(shortId)] HTTP \(statusCode) | x-ms-request-id: \(reqId)", tag: "BackupEngine")
            }
            handleUploadFailure(assetId: assetId, error: "HTTP \(statusCode)")
        }

        Task { await processQueue() }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64,
                    totalBytesExpectedToSend: Int64) {
        let key = String(task.taskIdentifier)
        guard let assetId = taskMap[key] else { return }
        DispatchQueue.main.async {
            self.activeUploadItems[assetId]?.bytesSent = totalBytesSent
            if totalBytesExpectedToSend > 0 {
                self.activeUploadItems[assetId]?.totalBytes = totalBytesExpectedToSend
            }
        }
    }

    private func handleUploadFailure(assetId: String, error: String) {
        guard let record = try? db.record(for: assetId) else { return }
        let shortId = String(assetId.prefix(8))
        if record.retries >= maxRetries - 1 {
            try? db.markPermFailed(assetId: assetId, error: error)
            DispatchQueue.main.async {
                AppLogger.shared.error("[\(shortId)] Perm failed after \(maxRetries) retries: \(error)", tag: "BackupEngine")
            }
        } else {
            try? db.incrementRetry(assetId: assetId)
            try? db.updateStatus(assetId: assetId, status: .failed, error: error)
            DispatchQueue.main.async {
                AppLogger.shared.warn("[\(shortId)] Retry \(record.retries + 1)/\(maxRetries): \(error)", tag: "BackupEngine")
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}
