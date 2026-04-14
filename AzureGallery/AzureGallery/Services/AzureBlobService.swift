import Foundation
import CryptoKit

/// Azure Blob Storage REST client using Shared Key (HMAC-SHA256) authentication.
///
/// Each request is signed by building a canonical string-to-sign from the HTTP method,
/// content headers, `x-ms-*` headers, and the canonicalized resource path, then
/// computing HMAC-SHA256 with the decoded account key.
///
/// Reference: https://learn.microsoft.com/en-us/rest/api/storageservices/authorize-with-shared-key
struct AzureBlobService {
    private static let apiVersion = "2024-11-04"

    let config: AzureConfig

    // MARK: - Public API

    /// Build a signed URLRequest for uploading a blob (to be used with URLSession background task).
    func uploadRequest(blobName: String, contentType: String, fileSize: Int64, accessTier: String? = nil) throws -> URLRequest {
        let url = config.blobURL(blobName: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        request.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        if let tier = accessTier {
            request.setValue(tier, forHTTPHeaderField: "x-ms-access-tier")
        }
        // All x-ms-* headers MUST be set before sign() — they are included in the HMAC.
        try sign(&request, contentLength: fileSize, contentType: contentType)
        return request
    }

    /// Download a blob's contents.
    func downloadBlob(blobName: String) async throws -> Data {
        let url = config.blobURL(blobName: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try sign(&request, contentLength: 0, contentType: "")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw AzureError.unexpectedStatus(code) }
        return data
    }

    /// Download a range of bytes from a blob (Range GET).
    func downloadBlobRange(blobName: String, offset: Int64 = 0, length: Int64 = 65536) async throws -> Data {
        let url = config.blobURL(blobName: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
        try sign(&request, contentLength: 0, contentType: "")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 206 else { throw AzureError.unexpectedStatus(code) }
        return data
    }

    /// Container storage stats: total blob count and total bytes.
    func containerStats() async throws -> (blobCount: Int, totalBytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        var marker: String? = nil

        repeat {
            var components = URLComponents(url: config.containerURL(), resolvingAgainstBaseURL: false)!
            var queryItems = [
                URLQueryItem(name: "restype", value: "container"),
                URLQueryItem(name: "comp", value: "list"),
            ]
            if let m = marker { queryItems.append(URLQueryItem(name: "marker", value: m)) }
            components.queryItems = queryItems
            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            try sign(&request, contentLength: 0, contentType: "")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AzureError.unexpectedStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            let parser = BlobStatsParser()
            let xml = XMLParser(data: data)
            xml.delegate = parser
            xml.parse()
            count += parser.blobCount
            bytes += parser.totalBytes
            marker = parser.nextMarker
        } while marker != nil

        return (count, bytes)
    }

    /// Check if a blob exists (HEAD request). Returns true if 200, false if 404.
    func blobExists(blobName: String) async throws -> Bool {
        let url = config.blobURL(blobName: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        try sign(&request, contentLength: 0, contentType: "")
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 { return true }
        if code == 404 { return false }
        throw AzureError.unexpectedStatus(code)
    }

    /// List blobs in the container (returns flat list of blob names).
    func listBlobs(prefix: String? = nil) async throws -> [String] {
        var components = URLComponents(url: config.containerURL(), resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "restype", value: "container"),
            URLQueryItem(name: "comp", value: "list")
        ]
        if let prefix { queryItems.append(URLQueryItem(name: "prefix", value: prefix)) }
        components.queryItems = queryItems
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        try sign(&request, contentLength: 0, contentType: "")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AzureError.unexpectedStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try parseListResponse(data)
    }

    /// Validate connection by checking that the container exists.
    func validateConnection() async throws {
        var components = URLComponents(url: config.containerURL(), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "restype", value: "container")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        try sign(&request, contentLength: 0, contentType: "")
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 || code == 206 { return }
        if code == 404 { throw AzureError.containerNotFound }
        if code == 403 { throw AzureError.unauthorized }
        throw AzureError.unexpectedStatus(code)
    }

    // MARK: - Shared Key Signing

    private func sign(_ request: inout URLRequest, contentLength: Int64, contentType: String) throws {
        let date = rfc1123Date()
        request.setValue(date, forHTTPHeaderField: "x-ms-date")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "x-ms-version")

        let stringToSign = buildStringToSign(request: request, contentLength: contentLength, contentType: contentType)
        let signature = try computeHMAC(string: stringToSign)
        request.setValue("SharedKey \(config.accountName):\(signature)", forHTTPHeaderField: "Authorization")
    }

    private func buildStringToSign(request: URLRequest, contentLength: Int64, contentType: String) -> String {
        let method = request.httpMethod ?? "GET"
        let contentLengthStr = contentLength > 0 ? String(contentLength) : ""
        let contentTypeStr = contentType.isEmpty ? "" : contentType
        let canonicalizedHeaders = buildCanonicalizedHeaders(request: request)
        let canonicalizedResource = buildCanonicalizedResource(url: request.url!)

        return [
            method,
            "",          // Content-Encoding
            "",          // Content-Language
            contentLengthStr,
            "",          // Content-MD5
            contentTypeStr,
            "",          // Date (using x-ms-date instead)
            "",          // If-Modified-Since
            "",          // If-Match
            "",          // If-None-Match
            "",          // If-Unmodified-Since
            request.value(forHTTPHeaderField: "Range") ?? "",
            canonicalizedHeaders,
            canonicalizedResource
        ].joined(separator: "\n")
    }

    private func buildCanonicalizedHeaders(request: URLRequest) -> String {
        guard let headers = request.allHTTPHeaderFields else { return "" }
        let msHeaders = headers
            .filter { $0.key.lowercased().hasPrefix("x-ms-") }
            .map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespaces)) }
            .sorted { $0.0 < $1.0 }
        return msHeaders.map { "\($0.0):\($0.1)" }.joined(separator: "\n")
    }

    private func buildCanonicalizedResource(url: URL) -> String {
        var result = "/\(config.accountName)\(url.path)"

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems, !queryItems.isEmpty else {
            return result
        }

        // Group params, sort by name
        var params: [String: [String]] = [:]
        for item in queryItems {
            params[item.name.lowercased(), default: []].append(item.value ?? "")
        }
        let sorted = params.sorted { $0.key < $1.key }
        for (key, values) in sorted {
            result += "\n\(key):\(values.sorted().joined(separator: ","))"
        }
        return result
    }

    private func computeHMAC(string: String) throws -> String {
        guard let data = string.data(using: .utf8) else { throw AzureError.signingFailed }
        let key = SymmetricKey(data: config.accountKey)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: key)
        return Data(signature).base64EncodedString()
    }

    // MARK: - Helpers

    private func rfc1123Date() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
        formatter.timeZone = TimeZone(abbreviation: "GMT")
        return formatter.string(from: Date())
    }

    private func parseListResponse(_ data: Data) throws -> [String] {
        let parser = BlobListParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = parser
        xmlParser.parse()
        return parser.blobNames
    }
}

// MARK: - Errors

enum AzureError: LocalizedError {
    case containerNotFound
    case unauthorized
    case unexpectedStatus(Int)
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .containerNotFound: return "Azure container not found. Check container name."
        case .unauthorized: return "Azure authentication failed. Check connection string."
        case .unexpectedStatus(let code): return "Azure returned HTTP \(code)"
        case .signingFailed: return "Failed to sign Azure request"
        }
    }
}

// MARK: - XML Parser for List Blobs

private final class BlobListParser: NSObject, XMLParserDelegate {
    var blobNames: [String] = []
    private var currentElement = ""
    private var currentName = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "Name" { currentName = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "Name" { currentName += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "Name" && !currentName.isEmpty {
            blobNames.append(currentName)
        }
    }
}

// MARK: - XML Parser for Container Stats (blob count + total size)

private final class BlobStatsParser: NSObject, XMLParserDelegate {
    var blobCount = 0
    var totalBytes: Int64 = 0
    var nextMarker: String?
    private var currentElement = ""
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "Content-Length" || elementName == "NextMarker" {
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "Content-Length" || currentElement == "NextMarker" {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "Content-Length", let size = Int64(currentText) {
            totalBytes += size
            blobCount += 1
        } else if elementName == "NextMarker" && !currentText.isEmpty {
            nextMarker = currentText
        }
    }
}
