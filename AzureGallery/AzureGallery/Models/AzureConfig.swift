import Foundation

/// Resolved Azure Blob Storage connection parameters.
///
/// Created by parsing an Azure connection string (from Keychain) plus a container name.
/// All URL helpers are derived from these fields — no network calls are made at construction.
struct AzureConfig {
    let accountName: String
    /// Raw 32-byte HMAC-SHA256 signing key decoded from the base64 AccountKey field.
    let accountKey: Data
    let containerName: String
    /// Usually "core.windows.net"; overridden for Azurite or sovereign clouds.
    let endpointSuffix: String

    /// Base URL for the Blob service, e.g. `https://myaccount.blob.core.windows.net`.
    var blobEndpoint: String {
        "https://\(accountName).blob.\(endpointSuffix)"
    }

    /// Full URL for a specific blob, percent-encoding the blob path.
    func blobURL(blobName: String) -> URL {
        URL(string: "\(blobEndpoint)/\(containerName)/\(blobName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? blobName)")!
    }

    /// URL for the container root (used for list and validate requests).
    func containerURL() -> URL {
        URL(string: "\(blobEndpoint)/\(containerName)")!
    }
}

extension AzureConfig {
    /// Errors thrown by ``AzureConfig/parse(connectionString:containerName:)``.
    enum ParseError: LocalizedError {
        case missingField(String)
        case invalidBase64Key

        var errorDescription: String? {
            switch self {
            case .missingField(let f): return "Connection string missing field: \(f)"
            case .invalidBase64Key: return "AccountKey is not valid base64"
            }
        }
    }

    /// Parse a semicolon-delimited Azure connection string into an ``AzureConfig``.
    ///
    /// Expected format: `DefaultEndpointsProtocol=https;AccountName=…;AccountKey=…;EndpointSuffix=…`
    /// - `EndpointSuffix` defaults to `core.windows.net` if omitted.
    /// - `containerName` defaults to `"photos"` when the caller passes an empty string.
    static func parse(connectionString: String, containerName: String) throws -> AzureConfig {
        var params: [String: String] = [:]
        for component in connectionString.components(separatedBy: ";") {
            guard let equalRange = component.range(of: "=") else { continue }
            let key = String(component[component.startIndex..<equalRange.lowerBound])
            let value = String(component[equalRange.upperBound...])
            if !key.isEmpty {
                params[key] = value
            }
        }

        guard let accountName = params["AccountName"] else {
            throw ParseError.missingField("AccountName")
        }
        guard let accountKeyString = params["AccountKey"] else {
            throw ParseError.missingField("AccountKey")
        }
        guard let accountKey = Data(base64Encoded: accountKeyString) else {
            throw ParseError.invalidBase64Key
        }

        let endpointSuffix = params["EndpointSuffix"] ?? "core.windows.net"

        return AzureConfig(
            accountName: accountName,
            accountKey: accountKey,
            containerName: containerName.isEmpty ? "photos" : containerName,
            endpointSuffix: endpointSuffix
        )
    }
}
