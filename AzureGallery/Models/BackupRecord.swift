import Foundation
import GRDB

enum BackupStatus: String, Codable, DatabaseValueConvertible {
    case pending
    case uploading
    case uploaded
    case failed
    case permFailed = "perm_failed"
}

struct BackupRecord: Codable, Identifiable {
    var id: Int64?
    var assetId: String
    var blobName: String
    var size: Int64?
    var mediaType: String
    var creationDate: String?
    var status: BackupStatus
    var retries: Int
    var uploadedAt: String?
    var error: String?
    var createdAt: String

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
    }
}

extension BackupRecord: FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "backups"

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let assetId = Column(CodingKeys.assetId)
        static let status = Column(CodingKeys.status)
        static let retries = Column(CodingKeys.retries)
        static let uploadedAt = Column(CodingKeys.uploadedAt)
        static let error = Column(CodingKeys.error)
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
