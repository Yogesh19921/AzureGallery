import Foundation

/// Abstraction over cloud blob storage backends (Azure, S3, GCP).
///
/// `BackupEngine` and all download/restore code use this protocol instead of
/// referencing a concrete provider directly. To add a new provider:
/// 1. Implement this protocol (signing, upload, download, stats)
/// 2. Add a setup view for credentials
/// 3. Register the provider in `CloudStorageFactory`
protocol CloudStorageProvider {
    /// Human-readable name for logs ("Azure", "Amazon S3", "Google Cloud").
    var providerName: String { get }

    /// Build a signed URLRequest for a background upload task.
    func uploadRequest(blobName: String, contentType: String, fileSize: Int64, accessTier: String?) throws -> URLRequest

    /// Download a blob's full contents.
    func downloadBlob(blobName: String) async throws -> Data

    /// Download a byte range (for thumbnail previews).
    func downloadBlobRange(blobName: String, offset: Int64, length: Int64) async throws -> Data

    /// Check whether a blob already exists (HEAD request).
    func blobExists(blobName: String) async throws -> Bool

    /// Aggregate stats: total blob count and total bytes in the container/bucket.
    func containerStats() async throws -> (blobCount: Int, totalBytes: Int64)

    /// Validate that the credentials work (e.g. container/bucket exists and is accessible).
    func validate() async throws
}

// MARK: - Provider Types

enum CloudProviderType: String, CaseIterable, Identifiable {
    case azure = "Azure"
    case s3    = "Amazon S3"
    case gcp   = "Google Cloud"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .azure: return "cloud.fill"
        case .s3:    return "shippingbox.fill"
        case .gcp:   return "globe"
        }
    }

    /// UserDefaults key for the "enabled" toggle.
    var enabledKey: String { "provider.\(rawValue).enabled" }

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var isConfigured: Bool {
        switch self {
        case .azure:
            return KeychainHelper.load(key: KeychainHelper.connectionStringKey) != nil
        case .s3:
            return KeychainHelper.load(key: KeychainHelper.s3AccessKeyIdKey) != nil
        case .gcp:
            return KeychainHelper.load(key: KeychainHelper.gcpAccessKeyKey) != nil
        }
    }
}

// MARK: - Factory

enum CloudStorageFactory {
    /// Returns the first configured+enabled provider (used for single-provider paths like download).
    static func makeProvider() -> CloudStorageProvider? {
        makeAllEnabled().first
    }

    /// Returns all enabled providers that have valid credentials.
    /// Used by `BackupEngine` to upload to multiple services.
    static func makeAllEnabled() -> [CloudStorageProvider] {
        var providers: [CloudStorageProvider] = []
        for type in CloudProviderType.allCases {
            guard type.isEnabled || isLegacySingleProvider(type) else { continue }
            if let p = makeProvider(for: type) { providers.append(p) }
        }
        return providers
    }

    /// Build a provider for a specific type, or nil if credentials are missing.
    static func makeProvider(for type: CloudProviderType) -> CloudStorageProvider? {
        switch type {
        case .azure: return makeAzure()
        case .s3:    return makeS3()
        case .gcp:   return makeGCP()
        }
    }

    // MARK: - Private builders

    private static func makeAzure() -> AzureBlobService? {
        guard let cs = KeychainHelper.load(key: KeychainHelper.connectionStringKey),
              let container = KeychainHelper.load(key: KeychainHelper.containerNameKey),
              let config = try? AzureConfig.parse(connectionString: cs, containerName: container) else {
            return nil
        }
        return AzureBlobService(config: config)
    }

    private static func makeS3() -> CloudStorageProvider? {
        guard let config = S3Config.fromKeychain() else { return nil }
        return S3BlobService(config: config)
    }

    private static func makeGCP() -> CloudStorageProvider? {
        guard let config = GCPConfig.fromKeychain() else { return nil }
        return GCPBlobService(config: config)
    }

    /// Backward compatibility: if user configured Azure before multi-provider was added,
    /// no "enabled" flag exists yet. Treat configured-but-no-flag as enabled.
    private static func isLegacySingleProvider(_ type: CloudProviderType) -> Bool {
        UserDefaults.standard.object(forKey: type.enabledKey) == nil && type.isConfigured
    }
}
