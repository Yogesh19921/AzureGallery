import Foundation

/// Resolved Amazon S3 connection parameters.
///
/// Created from user-supplied credentials (access key, secret, bucket, region).
/// All URL helpers are derived from these fields — no network calls are made at construction.
struct S3Config {
    let accessKeyId: String
    let secretAccessKey: String
    let bucket: String
    /// AWS region, e.g. `"us-east-1"`.
    let region: String

    /// The S3 endpoint derived from the region.
    /// Uses virtual-hosted-style: `https://<bucket>.s3.<region>.amazonaws.com`
    var endpoint: String {
        "https://\(bucket).s3.\(region).amazonaws.com"
    }

    /// Full URL for a specific object key (percent-encoding the key path).
    func objectURL(key: String) -> URL {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        return URL(string: "\(endpoint)/\(encoded)")!
    }

    /// URL for the bucket root (used for list and validate requests).
    func bucketURL() -> URL {
        URL(string: endpoint)!
    }
}

extension S3Config {
    /// Common AWS regions for the region picker.
    static let commonRegions: [(id: String, name: String)] = [
        ("us-east-1", "US East (N. Virginia)"),
        ("us-east-2", "US East (Ohio)"),
        ("us-west-1", "US West (N. California)"),
        ("us-west-2", "US West (Oregon)"),
        ("eu-west-1", "Europe (Ireland)"),
        ("eu-west-2", "Europe (London)"),
        ("eu-central-1", "Europe (Frankfurt)"),
        ("ap-southeast-1", "Asia Pacific (Singapore)"),
        ("ap-southeast-2", "Asia Pacific (Sydney)"),
        ("ap-northeast-1", "Asia Pacific (Tokyo)"),
        ("ap-south-1", "Asia Pacific (Mumbai)"),
        ("ca-central-1", "Canada (Central)"),
        ("sa-east-1", "South America (Sao Paulo)"),
    ]

    /// Load an S3Config from Keychain-stored credentials, or nil if any field is missing.
    static func fromKeychain() -> S3Config? {
        guard let accessKeyId = KeychainHelper.load(key: KeychainHelper.s3AccessKeyIdKey),
              let secretAccessKey = KeychainHelper.load(key: KeychainHelper.s3SecretAccessKeyKey),
              let bucket = KeychainHelper.load(key: KeychainHelper.s3BucketKey),
              let region = KeychainHelper.load(key: KeychainHelper.s3RegionKey) else {
            return nil
        }
        return S3Config(
            accessKeyId: accessKeyId,
            secretAccessKey: secretAccessKey,
            bucket: bucket,
            region: region
        )
    }
}
