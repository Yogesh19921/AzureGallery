import Foundation
import CryptoKit

/// Google Cloud Storage REST client using HMAC key authentication (AWS Signature V4 compatible).
///
/// GCS HMAC keys use the XML API which is S3-compatible. The signing algorithm is
/// identical to AWS Signature V4 but with these GCS-specific differences:
/// - Endpoint: `storage.googleapis.com` (path-style URLs)
/// - Region: always `"auto"` in the credential scope
/// - Service name in scope: `"s3"` (GCS HMAC reuses the S3 scope convention)
/// - Payload hash: `UNSIGNED-PAYLOAD`
///
/// Reference: https://cloud.google.com/storage/docs/authentication/hmackeys
struct GCPBlobService: CloudStorageProvider {
    let config: GCPConfig

    var providerName: String { "Google Cloud" }

    // MARK: - Storage Class Mapping

    /// Map the app's generic access tier names to GCS storage classes.
    static func gcsStorageClass(from accessTier: String?) -> String {
        switch accessTier {
        case nil, "Hot": return "STANDARD"
        case "Cool": return "NEARLINE"
        case "Cold": return "COLDLINE"
        case "Archive": return "ARCHIVE"
        default: return "STANDARD"
        }
    }

    // MARK: - CloudStorageProvider

    func uploadRequest(blobName: String, contentType: String, fileSize: Int64, accessTier: String? = nil) throws -> URLRequest {
        let url = config.objectURL(key: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        request.setValue("storage.googleapis.com", forHTTPHeaderField: "Host")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")

        let storageClass = Self.gcsStorageClass(from: accessTier)
        if storageClass != "STANDARD" {
            request.setValue(storageClass, forHTTPHeaderField: "x-goog-storage-class")
        }

        try signV4(&request, httpMethod: "PUT")
        return request
    }

    func downloadBlob(blobName: String) async throws -> Data {
        let url = config.objectURL(key: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("storage.googleapis.com", forHTTPHeaderField: "Host")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
        try signV4(&request, httpMethod: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw GCPError.unexpectedStatus(code) }
        return data
    }

    func downloadBlobRange(blobName: String, offset: Int64, length: Int64) async throws -> Data {
        let url = config.objectURL(key: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("storage.googleapis.com", forHTTPHeaderField: "Host")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
        request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
        try signV4(&request, httpMethod: "GET")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 206 else { throw GCPError.unexpectedStatus(code) }
        return data
    }

    func blobExists(blobName: String) async throws -> Bool {
        let url = config.objectURL(key: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("storage.googleapis.com", forHTTPHeaderField: "Host")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
        try signV4(&request, httpMethod: "HEAD")
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 { return true }
        if code == 404 { return false }
        throw GCPError.unexpectedStatus(code)
    }

    func containerStats() async throws -> (blobCount: Int, totalBytes: Int64) {
        var count = 0
        var bytes: Int64 = 0
        var continuationToken: String? = nil

        repeat {
            var components = URLComponents(url: config.bucketURL(), resolvingAgainstBaseURL: false)!
            var queryItems = [URLQueryItem(name: "list-type", value: "2")]
            if let token = continuationToken {
                queryItems.append(URLQueryItem(name: "continuation-token", value: token))
            }
            components.queryItems = queryItems

            var request = URLRequest(url: components.url!)
            request.httpMethod = "GET"
            request.setValue("storage.googleapis.com", forHTTPHeaderField: "Host")
            request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
            try signV4(&request, httpMethod: "GET")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw GCPError.unexpectedStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            }

            let parser = GCSListParser()
            let xml = XMLParser(data: data)
            xml.delegate = parser
            guard xml.parse(), xml.parserError == nil else { break }
            count += parser.objectCount
            bytes += parser.totalBytes
            continuationToken = parser.nextContinuationToken
        } while continuationToken != nil

        return (count, bytes)
    }

    func validate() async throws {
        // HEAD bucket to verify credentials and bucket existence.
        var request = URLRequest(url: config.bucketURL())
        request.httpMethod = "HEAD"
        request.setValue("storage.googleapis.com", forHTTPHeaderField: "Host")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
        try signV4(&request, httpMethod: "HEAD")
        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 { return }
        if code == 404 { throw GCPError.bucketNotFound }
        if code == 403 { throw GCPError.unauthorized }
        throw GCPError.unexpectedStatus(code)
    }

    // MARK: - AWS Signature V4 Signing (GCS HMAC compatible)

    /// Sign a request using AWS Signature V4, adapted for GCS HMAC keys.
    ///
    /// The credential scope uses region `"auto"` and service `"s3"` per GCS requirements.
    /// The payload hash is always `UNSIGNED-PAYLOAD` (GCS does not require content hashing).
    func signV4(_ request: inout URLRequest, httpMethod: String) throws {
        let now = Date()
        let dateStamp = Self.dateStamp(now)
        let amzDate = Self.amzDate(now)

        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")

        let credentialScope = "\(dateStamp)/auto/s3/aws4_request"

        // Build canonical request
        let canonicalHeaders = Self.canonicalHeaders(from: request)
        let signedHeaders = Self.signedHeaderNames(from: request)

        let canonicalURI = Self.canonicalURI(from: request.url!)
        let canonicalQueryString = Self.canonicalQueryString(from: request.url!)

        let canonicalRequest = [
            httpMethod,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders,
            "",  // blank line after headers
            signedHeaders,
            "UNSIGNED-PAYLOAD"
        ].joined(separator: "\n")

        // String to sign
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let stringToSign = [
            "AWS4-HMAC-SHA256",
            amzDate,
            credentialScope,
            canonicalRequestHash
        ].joined(separator: "\n")

        // Derive signing key
        let signingKey = try Self.deriveSigningKey(
            secret: config.secret,
            dateStamp: dateStamp,
            region: "auto",
            service: "s3"
        )

        // Compute signature
        let signature = Self.hmacSHA256(key: signingKey, data: Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let authorization = "AWS4-HMAC-SHA256 Credential=\(config.accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
    }

    // MARK: - Signing Helpers

    /// Derive the signing key: HMAC(HMAC(HMAC(HMAC("AWS4"+secret, date), region), service), "aws4_request")
    static func deriveSigningKey(secret: Data, dateStamp: String, region: String, service: String) throws -> Data {
        let kSecret = Data("AWS4".utf8) + secret
        let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        return kSigning
    }

    /// Compute HMAC-SHA256 and return raw bytes.
    static func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let signature = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(signature)
    }

    /// ISO 8601 basic date: "YYYYMMDD"
    static func dateStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: date)
    }

    /// ISO 8601 basic date-time: "YYYYMMDDTHHmmssZ"
    static func amzDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        return formatter.string(from: date)
    }

    /// Build canonical headers string (sorted, lowercased, trimmed).
    static func canonicalHeaders(from request: URLRequest) -> String {
        guard let headers = request.allHTTPHeaderFields else { return "" }
        let sorted = headers
            .map { ($0.key.lowercased(), $0.value.trimmingCharacters(in: .whitespaces)) }
            .sorted { $0.0 < $1.0 }
        return sorted.map { "\($0.0):\($0.1)" }.joined(separator: "\n")
    }

    /// Semicolon-delimited list of signed header names (sorted, lowercased).
    static func signedHeaderNames(from request: URLRequest) -> String {
        guard let headers = request.allHTTPHeaderFields else { return "" }
        return headers.keys
            .map { $0.lowercased() }
            .sorted()
            .joined(separator: ";")
    }

    /// URI-encode the path component for the canonical request.
    static func canonicalURI(from url: URL) -> String {
        let path = url.path
        return path.isEmpty ? "/" : path
    }

    /// Build the canonical query string (sorted by key, then value).
    static func canonicalQueryString(from url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems, !queryItems.isEmpty else {
            return ""
        }
        let sorted = queryItems.sorted {
            if $0.name == $1.name {
                return ($0.value ?? "") < ($1.value ?? "")
            }
            return $0.name < $1.name
        }
        return sorted.map { item in
            let name = Self.uriEncode(item.name)
            let value = Self.uriEncode(item.value ?? "")
            return "\(name)=\(value)"
        }.joined(separator: "&")
    }

    /// URI-encode per AWS Signature V4 rules: RFC 3986 unreserved characters are not encoded.
    static func uriEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }
}

// MARK: - Errors

enum GCPError: LocalizedError {
    case bucketNotFound
    case unauthorized
    case unexpectedStatus(Int)
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .bucketNotFound: return "GCS bucket not found. Check bucket name."
        case .unauthorized: return "GCS authentication failed. Check HMAC credentials."
        case .unexpectedStatus(let code): return "GCS returned HTTP \(code)"
        case .signingFailed: return "Failed to sign GCS request"
        }
    }
}

// MARK: - XML Parser for GCS List Objects V2

/// Parses the S3-compatible XML response from `GET /<bucket>?list-type=2`.
/// Extracts `<Key>`, `<Size>`, and `<NextContinuationToken>`.
private final class GCSListParser: NSObject, XMLParserDelegate {
    var objectCount = 0
    var totalBytes: Int64 = 0
    var nextContinuationToken: String?

    private var currentElement = ""
    private var currentText = ""
    private var inContents = false

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "Contents" {
            inContents = true
        }
        if elementName == "Size" || elementName == "NextContinuationToken" {
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "Size" || currentElement == "NextContinuationToken" {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        if elementName == "Contents" {
            inContents = false
            objectCount += 1
        } else if elementName == "Size" && inContents, let size = Int64(currentText) {
            totalBytes += size
        } else if elementName == "NextContinuationToken" && !currentText.isEmpty {
            nextContinuationToken = currentText
        }
    }
}
