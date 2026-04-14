import Foundation
import SwiftUI

// MARK: - Cache invalidation notification

extension Notification.Name {
    /// Posted on the main thread whenever the backup status cache is invalidated.
    /// `BackupCloudBadge` listens to this to refresh without a parent re-render.
    static let backupCacheInvalidated = Notification.Name("BackupBadge.cacheInvalidated")
}

// MARK: - Cache

/// Lightweight in-memory cache for per-asset BackupRecord lookups in the gallery.
/// Avoids hitting SQLite on every cell render. Must be accessed on the main thread.
enum BackupBadge {
    private static var cache: [String: BackupRecord] = [:]
    private static var loaded = false

    static func record(for assetId: String) -> BackupRecord? {
        if !loaded { preload() }
        return cache[assetId]
    }

    /// Drop the cache and notify all badge views to refresh.
    /// Always call this on the main thread (or dispatch to it).
    static func invalidate() {
        cache = [:]
        loaded = false
        NotificationCenter.default.post(name: .backupCacheInvalidated, object: nil)
    }

    private static func preload() {
        guard let rows = try? DatabaseService.shared.allRecords() else {
            // DB not ready yet — leave loaded=false so the next call retries.
            return
        }
        cache = Dictionary(uniqueKeysWithValues: rows.map { ($0.assetId, $0) })
        loaded = true   // only after data is actually in the cache
    }
}

// MARK: - Cloud badge overlay

/// Small cloud icon overlaid on a thumbnail showing backup status.
///
/// - `checkmark.icloud.fill` — photo has been successfully backed up (`.uploaded`)
/// - `icloud.and.arrow.up`   — photo is queued or uploading (`.pending` / `.uploading`)
/// - nothing                 — photo is not in the backup queue, or permanently failed
///
/// Uses `@State` + `.task` so it re-renders on first appear, and `.onReceive` so it
/// refreshes immediately when `BackupEngine` completes an upload and invalidates the cache.
struct BackupCloudBadge: View {
    let assetId: String

    @State private var status: BackupStatus? = nil

    var body: some View {
        Group {
            switch status {
            case .uploaded:
                Image(systemName: "checkmark.icloud.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.50), in: RoundedRectangle(cornerRadius: 5))

            case .pending, .uploading:
                Image(systemName: "icloud.and.arrow.up")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.40), in: RoundedRectangle(cornerRadius: 5))

            default:
                EmptyView()
            }
        }
        .task(id: assetId) {
            // Initial load: read from cache (which is populated by the time cells appear).
            status = BackupBadge.record(for: assetId)?.status
        }
        .onReceive(NotificationCenter.default.publisher(for: .backupCacheInvalidated)) { _ in
            // Cache was invalidated (e.g. upload just completed) — refresh immediately.
            status = BackupBadge.record(for: assetId)?.status
        }
    }
}
