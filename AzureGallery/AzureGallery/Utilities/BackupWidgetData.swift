import Foundation

/// Shared data structure used by both the app and a future WidgetKit extension.
///
/// The app writes fresh data after each upload via `save()`. A WidgetKit timeline
/// provider can read it back via `load()` to display up-to-date backup stats without
/// importing any heavy service dependencies.
///
/// Currently uses `UserDefaults.standard`. When a real App Group is configured for
/// the widget target, replace with `UserDefaults(suiteName: "group.com.yogesh.AzureGallery")`.
struct BackupWidgetData: Codable {
    let uploaded: Int
    let pending: Int
    let failed: Int
    let lastBackupDate: Date?

    /// Snapshot current backup statistics from the database.
    static func current() -> BackupWidgetData {
        let stats = (try? DatabaseService.shared.stats(totalInLibrary: 0)) ?? .empty
        return BackupWidgetData(
            uploaded: stats.uploaded,
            pending: stats.pendingTotal,
            failed: stats.allFailed,
            lastBackupDate: stats.lastUploadedAt
        )
    }

    /// Write to shared container for WidgetKit access.
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "widgetData")
    }

    /// Load previously saved widget data, or nil if nothing has been written yet.
    static func load() -> BackupWidgetData? {
        guard let data = UserDefaults.standard.data(forKey: "widgetData") else { return nil }
        return try? JSONDecoder().decode(BackupWidgetData.self, from: data)
    }
}
