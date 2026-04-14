import Foundation

struct BackupStats {
    let totalInLibrary: Int
    let uploaded: Int
    let pending: Int
    let uploading: Int
    let failed: Int
    let permFailed: Int
    let lastUploadedAt: Date?

    var pendingTotal: Int { pending + uploading }
    var allFailed: Int { failed + permFailed }

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
