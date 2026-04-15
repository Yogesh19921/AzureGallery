import Foundation

/// Resolved S3-compatible connection parameters.
///
/// Works with Amazon S3, Backblaze B2, Cloudflare R2, Wasabi, MinIO, and any
/// S3-compatible provider. The `customEndpoint` field overrides the default
/// AWS URL pattern when set.
struct S3Config {
    let accessKeyId: String
    let secretAccessKey: String
    let bucket: String
    /// AWS region or provider-specific region (e.g. "us-west-004" for Backblaze).
    let region: String
    /// Custom endpoint override. When nil, uses AWS: `https://<bucket>.s3.<region>.amazonaws.com`
    var customEndpoint: String? = nil

    /// The S3 endpoint. Uses custom endpoint if set, otherwise derives from region.
    var endpoint: String {
        if let custom = customEndpoint, !custom.isEmpty {
            // Custom endpoint — use path-style: https://endpoint/bucket
            let base = custom.hasPrefix("https://") ? custom : "https://\(custom)"
            return base.hasSuffix("/") ? "\(base)\(bucket)" : "\(base)/\(bucket)"
        }
        // AWS virtual-hosted-style
        return "https://\(bucket).s3.\(region).amazonaws.com"
    }

    /// Whether this config uses a custom (non-AWS) endpoint.
    var isCustomEndpoint: Bool {
        customEndpoint != nil && !customEndpoint!.isEmpty
    }

    func objectURL(key: String) -> URL {
        let encoded = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? key
        return URL(string: "\(endpoint)/\(encoded)")!
    }

    func bucketURL() -> URL {
        URL(string: endpoint)!
    }
}

// MARK: - Provider presets

extension S3Config {
    struct ProviderPreset: Identifiable {
        let id: String
        let name: String
        let endpointTemplate: String  // e.g. "s3.{region}.backblazeb2.com"
        let regions: [(id: String, name: String)]
        let helpText: String
    }

    static let presets: [ProviderPreset] = [
        ProviderPreset(
            id: "aws",
            name: "Amazon S3",
            endpointTemplate: "",  // empty = use default AWS URL
            regions: commonRegions,
            helpText: "Create an IAM user with S3 access in the AWS Console."
        ),
        ProviderPreset(
            id: "backblaze",
            name: "Backblaze B2",
            endpointTemplate: "s3.{region}.backblazeb2.com",
            regions: [
                ("us-west-004", "US West"),
                ("us-east-005", "US East"),
                ("eu-central-003", "EU Central"),
            ],
            helpText: "Use your B2 Application Key ID and Key. Find the endpoint in B2 → Buckets → Endpoint."
        ),
        ProviderPreset(
            id: "cloudflare",
            name: "Cloudflare R2",
            endpointTemplate: "{account_id}.r2.cloudflarestorage.com",
            regions: [("auto", "Auto")],
            helpText: "Use your R2 API token. Find the S3 endpoint in R2 → Settings → S3 API."
        ),
        ProviderPreset(
            id: "wasabi",
            name: "Wasabi",
            endpointTemplate: "s3.{region}.wasabisys.com",
            regions: [
                ("us-east-1", "US East 1"),
                ("us-east-2", "US East 2"),
                ("us-west-1", "US West 1"),
                ("eu-central-1", "EU Central 1"),
                ("ap-northeast-1", "AP Tokyo"),
            ],
            helpText: "Create an access key in Wasabi Console → Access Keys."
        ),
        ProviderPreset(
            id: "minio",
            name: "MinIO / Self-hosted",
            endpointTemplate: "custom",
            regions: [("us-east-1", "Default")],
            helpText: "Enter your MinIO server URL (e.g. minio.local:9000)."
        ),
        ProviderPreset(
            id: "digitalocean",
            name: "DigitalOcean Spaces",
            endpointTemplate: "{region}.digitaloceanspaces.com",
            regions: [
                ("nyc3", "New York"),
                ("sfo3", "San Francisco"),
                ("ams3", "Amsterdam"),
                ("sgp1", "Singapore"),
                ("fra1", "Frankfurt"),
            ],
            helpText: "Create a Spaces access key in DigitalOcean → API → Spaces Keys."
        ),
    ]

    /// Standard AWS regions.
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
            region: region,
            customEndpoint: KeychainHelper.load(key: KeychainHelper.s3EndpointKey)
        )
    }
}
