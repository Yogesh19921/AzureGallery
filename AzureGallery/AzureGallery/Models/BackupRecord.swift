import Foundation
@preconcurrency import GRDB

/// Upload lifecycle for a single PHAsset.
///
/// State machine: `pending` → `uploading` → `uploaded`
///                `uploading` → `failed` (retriable) → `permFailed` (exhausted retries)
enum BackupStatus: String, Sendable {
    case pending
    case uploading
    case uploaded
    case failed
    /// Permanently failed after exhausting all retries.
    case permFailed = "perm_failed"
}

/// SQLite row in the `backups` table. One record per PHAsset.
///
/// `assetId` mirrors `PHAsset.localIdentifier` and is the primary lookup key.
/// Vision metadata fields are populated after analysis, before upload.
struct BackupRecord: Identifiable, Sendable {
    /// Auto-assigned row ID by GRDB on first insert; nil before persistence.
    var id: Int64?
    var assetId: String
    var blobName: String
    var size: Int64?
    var mediaType: String
    var creationDate: String?
    var status: BackupStatus
    var retries: Int
    /// ISO-8601 timestamp set when the blob reaches `uploaded` status.
    var uploadedAt: String?
    /// Human-readable description of the most recent failure, if any.
    var error: String?
    /// ISO-8601 timestamp of when this record was first inserted.
    var createdAt: String
    // Vision metadata
    var faceCount: Int?
    var sceneLabels: String?    // JSON-encoded [String]
    var hasText: Bool

    init(
        assetId: String,
        blobName: String,
        size: Int64? = nil,
        mediaType: String,
        creationDate: String? = nil
    ) {
        self.assetId = assetId
        self.blobName = blobName
        self.size = size
        self.mediaType = mediaType
        self.creationDate = creationDate
        self.status = .pending
        self.retries = 0
        self.createdAt = ISO8601DateFormatter().string(from: Date())
        self.faceCount = nil
        self.sceneLabels = nil
        self.hasText = false
    }

    /// Decoded scene labels from the JSON-encoded `sceneLabels` column.
    /// Returns `[]` when the field is nil or contains malformed JSON.
    var sceneLabelsArray: [String] {
        guard let json = sceneLabels,
              let data = json.data(using: .utf8),
              let array = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        return array
    }
}

// MARK: - GRDB

extension BackupRecord: TableRecord {
    static let databaseTableName = "backups"
}

extension BackupRecord: FetchableRecord {
    init(row: Row) throws {
        id           = row["id"]
        assetId      = row["assetId"]
        blobName     = row["blobName"]
        size         = row["size"]
        mediaType    = row["mediaType"]
        creationDate = row["creationDate"]
        let statusRaw: String = row["status"]
        status       = BackupStatus(rawValue: statusRaw) ?? .pending
        retries      = row["retries"]
        uploadedAt   = row["uploadedAt"]
        error        = row["error"]
        createdAt    = row["createdAt"]
        faceCount    = row["faceCount"]
        sceneLabels  = row["sceneLabels"]
        hasText      = row["hasText"] ?? false
    }
}

extension BackupRecord: MutablePersistableRecord {
    func encode(to container: inout PersistenceContainer) throws {
        container["id"]           = id
        container["assetId"]      = assetId
        container["blobName"]     = blobName
        container["size"]         = size
        container["mediaType"]    = mediaType
        container["creationDate"] = creationDate
        container["status"]       = status.rawValue
        container["retries"]      = retries
        container["uploadedAt"]   = uploadedAt
        container["error"]        = error
        container["createdAt"]    = createdAt
        container["faceCount"]    = faceCount
        container["sceneLabels"]  = sceneLabels
        container["hasText"]      = hasText
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - Column helpers

extension BackupRecord {
    enum Columns {
        static let id         = Column("id")
        static let assetId    = Column("assetId")
        static let status     = Column("status")
        static let retries    = Column("retries")
        static let uploadedAt = Column("uploadedAt")
        static let error      = Column("error")
        static let faceCount  = Column("faceCount")
        static let hasText    = Column("hasText")
    }
}
