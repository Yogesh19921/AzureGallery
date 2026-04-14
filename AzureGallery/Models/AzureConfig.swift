import Foundation

struct AzureConfig {
    let accountName: String
    let accountKey: Data
    let containerName: String
    let endpointSuffix: String

    var blobEndpoint: String {
        "https://\(accountName).blob.\(endpointSuffix)"
    }

    func blobURL(blobName: String) -> URL {
        URL(string: "\(blobEndpoint)/\(containerName)/\(blobName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? blobName)")!
    }

    func containerURL() -> URL {
        URL(string: "\(blobEndpoint)/\(containerName)")!
    }
}

extension AzureConfig {
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
