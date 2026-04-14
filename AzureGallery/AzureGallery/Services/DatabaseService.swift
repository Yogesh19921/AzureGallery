import Foundation
@preconcurrency import GRDB

/// Manages all SQLite persistence for backup records via GRDB.
/// Single source of truth for backup state — the app never queries Azure to determine
/// what has been backed up during normal operation.
final class DatabaseService {
    static let shared = DatabaseService()

    private var dbQueue: DatabaseQueue!

    private init() {}

    func setup() throws {
        let dbURL = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AzureGallery.sqlite")

        dbQueue = try DatabaseQueue(path: dbURL.path)
        try migrate()
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_backups") { db in
            try db.create(table: "backups") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("assetId", .text).notNull().unique()
                t.column("blobName", .text).notNull()
                t.column("size", .integer)
                t.column("mediaType", .text).notNull()
                t.column("creationDate", .text)
                t.column("status", .text).notNull().defaults(to: "pending")
                t.column("retries", .integer).notNull().defaults(to: 0)
                t.column("uploadedAt", .text)
                t.column("error", .text)
                t.column("createdAt", .text).notNull()
            }
            try db.create(index: "idx_backups_status", on: "backups", columns: ["status"])
            try db.create(index: "idx_backups_asset", on: "backups", columns: ["assetId"])
        }

        migrator.registerMigration("v2_vision_metadata") { db in
            try db.alter(table: "backups") { t in
                t.add(column: "faceCount", .integer)
                t.add(column: "sceneLabels", .text)
                t.add(column: "hasText", .boolean).notNull().defaults(to: false)
            }
        }

        try migrator.migrate(dbQueue)
    }

    func updateVisionMetadata(assetId: String, faceCount: Int?, sceneLabels: [String], hasText: Bool) throws {
        let labelsJSON = sceneLabels.isEmpty ? nil :
            String(data: (try? JSONEncoder().encode(sceneLabels)) ?? Data(), encoding: .utf8)
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE backups SET faceCount = :fc, sceneLabels = :sl, hasText = :ht WHERE assetId = :id",
                arguments: ["fc": faceCount, "sl": labelsJSON, "ht": hasText, "id": assetId]
            )
        }
    }

    // MARK: - Queries

    func allRecords() throws -> [BackupRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM backups")
            return try rows.map { try BackupRecord(row: $0) }
        }
    }

    func upsert(_ record: inout BackupRecord) throws {
        try dbQueue.write { db in
            try record.save(db)
        }
    }

    func record(for assetId: String) throws -> BackupRecord? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM backups WHERE assetId = ?", arguments: [assetId]) else { return nil }
            return try BackupRecord(row: row)
        }
    }

    func allAssetIds() throws -> Set<String> {
        try dbQueue.read { db in
            let ids = try String.fetchAll(db, sql: "SELECT assetId FROM backups")
            return Set(ids)
        }
    }

    func pendingRecords(limit: Int = 50) throws -> [BackupRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM backups WHERE status = ? LIMIT ?", arguments: [BackupStatus.pending.rawValue, limit])
            return try rows.map { try BackupRecord(row: $0) }
        }
    }

    func updateStatus(assetId: String, status: BackupStatus, error: String? = nil) throws {
        try dbQueue.write { db in
            var updates: [String: DatabaseValue] = [
                "status": status.rawValue.databaseValue
            ]
            if let error {
                updates["error"] = error.databaseValue
            }
            if status == .uploaded {
                updates["uploadedAt"] = ISO8601DateFormatter().string(from: Date()).databaseValue
                updates["error"] = DatabaseValue.null
            }
            try db.execute(
                sql: "UPDATE backups SET status = :status, error = :error, uploadedAt = :uploadedAt WHERE assetId = :assetId",
                arguments: [
                    "status": status.rawValue,
                    "error": error,
                    "uploadedAt": status == .uploaded ? ISO8601DateFormatter().string(from: Date()) : nil,
                    "assetId": assetId
                ]
            )
        }
    }

    func incrementRetry(assetId: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE backups SET retries = retries + 1 WHERE assetId = :assetId",
                arguments: ["assetId": assetId]
            )
        }
    }

    func markPermFailed(assetId: String, error: String?) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE backups SET status = 'perm_failed', error = :error WHERE assetId = :assetId",
                arguments: ["error": error, "assetId": assetId]
            )
        }
    }

    func resetFailedToPending() throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE backups SET status = 'pending', retries = 0, error = NULL WHERE status IN ('failed', 'perm_failed')")
        }
    }

    /// Resets any records stuck in `.uploading` back to `.pending`.
    /// Called on launch — if the app was killed mid-upload the URLSession task is gone,
    /// so these records would never progress without a reset.
    func resetStaleUploading() throws {
        try dbQueue.write { db in
            try db.execute(sql: "UPDATE backups SET status = 'pending' WHERE status = 'uploading'")
        }
    }

    /// Aggregates backup counts across all status values.
    /// - Parameter totalInLibrary: Total asset count from PhotoKit (not tracked in DB).
    func stats(totalInLibrary: Int) throws -> BackupStats {
        try dbQueue.read { db in
            let uploaded = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'uploaded'") ?? 0
            let pending = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'pending'") ?? 0
            let uploading = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'uploading'") ?? 0
            let failed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'failed'") ?? 0
            let permFailed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'perm_failed'") ?? 0
            let lastDateStr = try String.fetchOne(db, sql: "SELECT MAX(uploadedAt) FROM backups WHERE uploadedAt IS NOT NULL")
            let lastDate = lastDateStr.flatMap { ISO8601DateFormatter().date(from: $0) }

            return BackupStats(
                totalInLibrary: totalInLibrary,
                uploaded: uploaded,
                pending: pending,
                uploading: uploading,
                failed: failed,
                permFailed: permFailed,
                lastUploadedAt: lastDate
            )
        }
    }
}

// MARK: - Testing support

extension DatabaseService {
    /// Creates an isolated in-memory DatabaseService for unit tests.
    /// Uses the same migrations as the production path, so schema is always in sync.
    static func makeInMemory() throws -> DatabaseService {
        let service = DatabaseService()
        // DatabaseQueue() with no path creates a private in-memory SQLite database
        service.dbQueue = try DatabaseQueue()
        try service.migrate()
        return service
    }
}
