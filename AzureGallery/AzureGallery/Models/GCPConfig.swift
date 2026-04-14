import Foundation

/// Resolved Google Cloud Storage connection parameters using HMAC key authentication.
///
/// GCS HMAC keys are compatible with AWS Signature V4 signing, using
/// `storage.googleapis.com` as the endpoint and path-style URLs.
/// No network calls are made at construction.
struct GCPConfig {
    /// HMAC access key (e.g. "GOOGTS7C7FUP3AIRVJTE2BCDKINBTES3HC2GY5CBFJDCQ2SYHV6A6XXVTJFSA").
    let accessKey: String
    /// HMAC secret — raw bytes decoded from the base64-encoded key provided by GCS.
    let secret: Data
    /// GCS bucket name.
    let bucket: String
    /// GCP project ID (optional, used for bucket-level operations).
    let projectId: String

    /// Full URL for a specific object key using path-style addressing.
    /// e.g. `https://storage.googleapis.com/<bucket>/<key>`
    func objectURL(key: String) -> URL {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        return URL(string: "https://storage.googleapis.com/\(bucket)/\(encoded)")!
    }

    /// URL for the bucket root.
    /// e.g. `https://storage.googleapis.com/<bucket>`
    func bucketURL() -> URL {
        URL(string: "https://storage.googleapis.com/\(bucket)")!
    }
}

extension GCPConfig {
    enum ConfigError: LocalizedError {
        case missingAccessKey
        case missingSecret
        case missingBucket
        case invalidBase64Secret

        var errorDescription: String? {
            switch self {
            case .missingAccessKey: return "GCP HMAC access key is required"
            case .missingSecret: return "GCP HMAC secret is required"
            case .missingBucket: return "GCS bucket name is required"
            case .invalidBase64Secret: return "GCP HMAC secret is not valid base64"
            }
        }
    }

    /// Load a GCPConfig from Keychain-stored credentials, or nil if any required field is missing.
    static func fromKeychain() -> GCPConfig? {
        guard let accessKey = KeychainHelper.load(key: KeychainHelper.gcpAccessKeyKey),
              let secretB64 = KeychainHelper.load(key: KeychainHelper.gcpSecretKey),
              let secret = Data(base64Encoded: secretB64),
              let bucket = KeychainHelper.load(key: KeychainHelper.gcpBucketKey) else {
            return nil
        }
        let projectId = KeychainHelper.load(key: KeychainHelper.gcpProjectIdKey) ?? ""
        return GCPConfig(
            accessKey: accessKey,
            secret: secret,
            bucket: bucket,
            projectId: projectId
        )
    }
}
