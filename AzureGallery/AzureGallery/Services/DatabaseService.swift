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

        migrator.registerMigration("v3_content_hash") { db in
            try db.alter(table: "backups") { t in
                t.add(column: "contentHash", .text)
            }
            try db.create(index: "idx_backups_hash", on: "backups", columns: ["contentHash"])
        }

        migrator.registerMigration("v4_bandwidth_stats") { db in
            try db.create(table: "bandwidth_stats") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("bytesUploaded", .integer).notNull()
                t.column("dateKey", .text).notNull()
                t.column("monthKey", .text).notNull()
                t.column("recordedAt", .text).notNull()
            }
            try db.create(index: "idx_bw_date", on: "bandwidth_stats", columns: ["dateKey"])
            try db.create(index: "idx_bw_month", on: "bandwidth_stats", columns: ["monthKey"])
        }

        migrator.registerMigration("v5_search_text") { db in
            try db.alter(table: "backups") { t in
                t.add(column: "recognizedText", .text)    // full OCR text, newline-separated
                t.add(column: "animalLabels", .text)      // JSON-encoded [String]
            }
        }

        try migrator.migrate(dbQueue)
    }

    func updateVisionMetadata(assetId: String, faceCount: Int?, sceneLabels: [String], hasText: Bool,
                              recognizedText: [String] = [], animalLabels: [String] = []) throws {
        let labelsJSON = sceneLabels.isEmpty ? nil :
            String(data: (try? JSONEncoder().encode(sceneLabels)) ?? Data(), encoding: .utf8)
        let ocrText = recognizedText.isEmpty ? nil : recognizedText.joined(separator: "\n")
        let animalsJSON = animalLabels.isEmpty ? nil :
            String(data: (try? JSONEncoder().encode(animalLabels)) ?? Data(), encoding: .utf8)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE backups SET faceCount = :fc, sceneLabels = :sl, hasText = :ht,
                       recognizedText = :ocr, animalLabels = :al WHERE assetId = :id
                """,
                arguments: ["fc": faceCount, "sl": labelsJSON, "ht": hasText,
                            "ocr": ocrText, "al": animalsJSON, "id": assetId]
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

    /// Returns asset IDs of records that have NULL animalLabels (need Vision re-analysis).
    func assetIdsNeedingAnalysis(limit: Int = 100) throws -> [String] {
        try dbQueue.read { db in
            try String.fetchAll(db, sql: "SELECT assetId FROM backups WHERE animalLabels IS NULL LIMIT ?", arguments: [limit])
        }
    }

    /// Search backed-up records using Vision metadata. Searches scene labels, OCR text, and animal labels.
    func searchRecords(hasText: Bool? = nil, minFaces: Int? = nil, sceneKeyword: String? = nil,
                       textQuery: String? = nil, limit: Int = 200) throws -> [BackupRecord] {
        try dbQueue.read { db in
            var conditions: [String] = []
            var args: [any DatabaseValueConvertible] = []
            if hasText == true { conditions.append("hasText = 1") }
            if let min = minFaces { conditions.append("faceCount >= ?"); args.append(min) }
            if let kw = sceneKeyword, !kw.isEmpty {
                conditions.append("(sceneLabels LIKE ? OR animalLabels LIKE ?)")
                args.append("%\(kw)%"); args.append("%\(kw)%")
            }
            if let tq = textQuery, !tq.isEmpty {
                conditions.append("recognizedText LIKE ?")
                args.append("%\(tq)%")
            }
            let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
            let sql = "SELECT * FROM backups \(whereClause) LIMIT ?"
            args.append(limit)
            let rows = try Row.fetchAll(db, sql: sql, arguments: StatementArguments(args))
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

    /// Returns the number of records with `pending` status.
    func pendingCount() throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'pending'") ?? 0
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

    /// Removes pending / failed records whose assetId is NOT in `allowedIds`.
    /// Already-uploaded records are kept (they represent completed work).
    /// Pass `nil` to skip purging (all photos allowed). Pass empty set to purge everything non-uploaded.
    func purgeNonUploadedNotIn(allowedIds: Set<String>?) throws {
        guard let allowed = allowedIds else { return } // nil = everything allowed
        try dbQueue.write { db in
            if allowed.isEmpty {
                try db.execute(sql: "DELETE FROM backups WHERE status NOT IN ('uploaded', 'uploading')")
            } else {
                let rows = try String.fetchAll(db, sql: "SELECT assetId FROM backups WHERE status NOT IN ('uploaded', 'uploading')")
                let toDelete = rows.filter { !allowed.contains($0) }
                for id in toDelete {
                    try db.execute(sql: "DELETE FROM backups WHERE assetId = ?", arguments: [id])
                }
            }
        }
    }

    /// Returns all records with status `uploaded`, ordered by creationDate descending.
    func uploadedRecords() throws -> [BackupRecord] {
        try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM backups WHERE status = 'uploaded' ORDER BY creationDate DESC")
            return try rows.map { try BackupRecord(row: $0) }
        }
    }

    // MARK: - Content Hash

    /// Returns the first backup record matching the given SHA-256 content hash, or nil.
    func recordByHash(hash: String) throws -> BackupRecord? {
        try dbQueue.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM backups WHERE contentHash = ? LIMIT 1", arguments: [hash]) else { return nil }
            return try BackupRecord(row: row)
        }
    }

    /// Stores the SHA-256 content hash for a given asset.
    func updateHash(assetId: String, hash: String) throws {
        try dbQueue.write { db in
            try db.execute(
                sql: "UPDATE backups SET contentHash = :hash WHERE assetId = :assetId",
                arguments: ["hash": hash, "assetId": assetId]
            )
        }
    }

    // MARK: - Bandwidth Stats

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Records a successful upload's byte count for bandwidth tracking.
    func recordUpload(bytes: Int64, date: Date) throws {
        let dateKey = DatabaseService.dateKeyFormatter.string(from: date)
        let monthKey = DatabaseService.monthKeyFormatter.string(from: date)
        let recordedAt = ISO8601DateFormatter().string(from: date)
        try dbQueue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO bandwidth_stats (bytesUploaded, dateKey, monthKey, recordedAt)
                    VALUES (:bytes, :dateKey, :monthKey, :recordedAt)
                    """,
                arguments: ["bytes": bytes, "dateKey": dateKey, "monthKey": monthKey, "recordedAt": recordedAt]
            )
        }
    }

    /// Total bytes uploaded on the current UTC calendar day.
    func bytesUploadedToday() throws -> Int64 {
        let todayKey = DatabaseService.dateKeyFormatter.string(from: Date())
        return try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(bytesUploaded), 0) FROM bandwidth_stats WHERE dateKey = ?", arguments: [todayKey]) ?? 0
        }
    }

    /// Total bytes uploaded in the current UTC calendar month.
    func bytesUploadedThisMonth() throws -> Int64 {
        let monthKey = DatabaseService.monthKeyFormatter.string(from: Date())
        return try dbQueue.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(bytesUploaded), 0) FROM bandwidth_stats WHERE monthKey = ?", arguments: [monthKey]) ?? 0
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
        let todayKey = DatabaseService.dateKeyFormatter.string(from: Date())
        let monthKey = DatabaseService.monthKeyFormatter.string(from: Date())
        return try dbQueue.read { db in
            let uploaded = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'uploaded'") ?? 0
            let pending = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'pending'") ?? 0
            let uploading = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'uploading'") ?? 0
            let failed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'failed'") ?? 0
            let permFailed = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM backups WHERE status = 'perm_failed'") ?? 0
            let lastDateStr = try String.fetchOne(db, sql: "SELECT MAX(uploadedAt) FROM backups WHERE uploadedAt IS NOT NULL")
            let lastDate = lastDateStr.flatMap { ISO8601DateFormatter().date(from: $0) }
            let bytesToday = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(bytesUploaded), 0) FROM bandwidth_stats WHERE dateKey = ?", arguments: [todayKey]) ?? 0
            let bytesThisMonth = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(bytesUploaded), 0) FROM bandwidth_stats WHERE monthKey = ?", arguments: [monthKey]) ?? 0

            return BackupStats(
                totalInLibrary: totalInLibrary,
                uploaded: uploaded,
                pending: pending,
                uploading: uploading,
                failed: failed,
                permFailed: permFailed,
                lastUploadedAt: lastDate,
                bytesToday: bytesToday,
                bytesThisMonth: bytesThisMonth
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
