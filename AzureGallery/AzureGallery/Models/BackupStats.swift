import Foundation

/// Aggregate counts used by the backup status UI.
///
/// Computed from the `backups` table via ``DatabaseService/stats(totalInLibrary:)``.
/// `totalInLibrary` is passed in from `PhotoLibraryService.totalCount` because it
/// reflects the live PHFetchResult count, not the DB row count.
struct BackupStats {
    let totalInLibrary: Int
    let uploaded: Int
    let pending: Int
    let uploading: Int
    let failed: Int
    let permFailed: Int
    /// Date of the most recently completed upload, or nil if nothing has been uploaded yet.
    let lastUploadedAt: Date?

    /// Sum of pending + uploading (items still in the work queue).
    var pendingTotal: Int { pending + uploading }
    /// Sum of failed + permFailed (items that need attention).
    var allFailed: Int { failed + permFailed }

    /// Zero-value placeholder used before the database is queried.
    static let empty = BackupStats(
        totalInLibrary: 0,
        uploaded: 0,
        pending: 0,
        uploading: 0,
        failed: 0,
        permFailed: 0,
        lastUploadedAt: nil
    )
}
