import Foundation
import CryptoKit

/// Amazon S3 REST client using AWS Signature V4 (HMAC-SHA256) authentication.
///
/// Each request is signed per the AWS Signature Version 4 process:
/// 1. Build a canonical request (method, URI, query, headers, payload hash)
/// 2. Build a string to sign (algorithm, timestamp, scope, hash of canonical request)
/// 3. Derive a signing key via chained HMAC (secret → date → region → service → "aws4_request")
/// 4. Compute HMAC-SHA256 of the string to sign with the derived key
/// 5. Attach the Authorization header
///
/// Reference: https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-authenticating-requests.html
struct S3BlobService: CloudStorageProvider {
    let config: S3Config

    var providerName: String { "Amazon S3" }

    /// SHA-256 hash of an empty payload (used for GET/HEAD/DELETE requests).
    private static let emptyPayloadHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    /// Sentinel value for unsigned payloads (used for background upload requests
    /// where the file content is not available at signing time).
    private static let unsignedPayload = "UNSIGNED-PAYLOAD"

    // MARK: - Storage Class Mapping

    /// Maps the app's generic access tier names to S3 storage class values.
    static func storageClass(forTier tier: String) -> String? {
        switch tier {
        case "Hot": return "STANDARD"
        case "Cool": return "STANDARD_IA"
        case "Cold": return "GLACIER_IR"
        case "Archive": return "DEEP_ARCHIVE"
        default: return nil
        }
    }

    // MARK: - CloudStorageProvider

    func uploadRequest(blobName: String, contentType: String, fileSize: Int64, accessTier: String? = nil) throws -> URLRequest {
        let url = config.objectURL(key: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")

        if let tier = accessTier, let s3Class = Self.storageClass(forTier: tier) {
            request.setValue(s3Class, forHTTPHeaderField: "x-amz-storage-class")
        }

        try sign(&request, payloadHash: Self.unsignedPayload)
        return request
    }

    func downloadBlob(blobName: String) async throws -> Data {
        let url = config.objectURL(key: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        try sign(&request, payloadHash: Self.emptyPayloadHash)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw S3Error.unexpectedStatus(code) }
        return data
    }

    func downloadBlobRange(blobName: String, offset: Int64, length: Int64) async throws -> Data {
        let url = config.objectURL(key: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=\(offset)-\(offset + length - 1)", forHTTPHeaderField: "Range")
        try sign(&request, payloadHash: Self.emptyPayloadHash)

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 206 else { throw S3Error.unexpectedStatus(code) }
        return data
    }

    func blobExists(blobName: String) async throws -> Bool {
        let url = config.objectURL(key: blobName)
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        try sign(&request, payloadHash: Self.emptyPayloadHash)

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 { return true }
        if code == 404 { return false }
        throw S3Error.unexpectedStatus(code)
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
            try sign(&request, payloadHash: Self.emptyPayloadHash)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                throw S3Error.unexpectedStatus((response as? HTTPURLResponse)?.statusCode ?? 0)
            }

            let parser = S3ListParser()
            let xml = XMLParser(data: data)
            xml.delegate = parser
            guard xml.parse(), xml.parserError == nil else { break }

            count += parser.objectCount
            bytes += parser.totalBytes
            continuationToken = parser.isTruncated ? parser.nextContinuationToken : nil
        } while continuationToken != nil

        return (count, bytes)
    }

    func validate() async throws {
        // HEAD bucket: sends a HEAD request to the bucket URL.
        var request = URLRequest(url: config.bucketURL())
        request.httpMethod = "HEAD"
        try sign(&request, payloadHash: Self.emptyPayloadHash)

        let (_, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 || code == 204 || code == 301 { return }
        if code == 404 { throw S3Error.bucketNotFound }
        if code == 403 { throw S3Error.unauthorized }
        throw S3Error.unexpectedStatus(code)
    }

    // MARK: - AWS Signature V4 Signing

    /// Signs the given request using AWS Signature Version 4.
    ///
    /// All headers that participate in signing (Host, x-amz-*, Content-Type)
    /// **must** be set on the request before calling this method.
    private func sign(_ request: inout URLRequest, payloadHash: String) throws {
        let now = Date()
        let amzDate = Self.amzDateFormatter.string(from: now)
        let dateStamp = Self.dateStampFormatter.string(from: now)

        let host = request.url!.host!
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "x-amz-date")
        request.setValue(payloadHash, forHTTPHeaderField: "x-amz-content-sha256")

        let scope = "\(dateStamp)/\(config.region)/s3/aws4_request"

        // Step 1: Canonical request
        let canonicalRequest = buildCanonicalRequest(request: request, payloadHash: payloadHash)

        // Step 2: String to sign
        let canonicalRequestHash = SHA256.hash(data: Data(canonicalRequest.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let stringToSign = "AWS4-HMAC-SHA256\n\(amzDate)\n\(scope)\n\(canonicalRequestHash)"

        // Step 3: Signing key
        let signingKey = try deriveSigningKey(secret: config.secretAccessKey, dateStamp: dateStamp,
                                               region: config.region, service: "s3")

        // Step 4: Signature
        let signature = hmacSHA256(key: signingKey, data: Data(stringToSign.utf8))
            .map { String(format: "%02x", $0) }.joined()

        // Step 5: Authorization header
        let signedHeaders = self.signedHeaders(request: request)
        let authHeader = "AWS4-HMAC-SHA256 Credential=\(config.accessKeyId)/\(scope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }

    /// Build the canonical request string per AWS Sig V4 spec.
    private func buildCanonicalRequest(request: URLRequest, payloadHash: String) -> String {
        let method = request.httpMethod ?? "GET"
        let canonicalURI = canonicalPath(for: request.url!)
        let canonicalQueryString = buildCanonicalQueryString(url: request.url!)
        let (canonicalHeaders, signedHeadersList) = buildCanonicalHeaders(request: request)

        return [
            method,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders,
            "",  // trailing newline after headers (canonicalHeaders already ends with \n)
            signedHeadersList,
            payloadHash,
        ].joined(separator: "\n")
    }

    /// Returns the URL path, percent-encoded per S3 requirements.
    /// For virtual-hosted-style URLs, the path is just `/<key>`.
    private func canonicalPath(for url: URL) -> String {
        let path = url.path
        if path.isEmpty { return "/" }
        // Re-encode each path segment (S3 requires RFC 3986 percent-encoding)
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        let encoded = segments.map { segment -> String in
            let s = String(segment)
            return s.addingPercentEncoding(withAllowedCharacters: Self.uriUnreserved) ?? s
        }
        let result = encoded.joined(separator: "/")
        return result.isEmpty ? "/" : result
    }

    /// Characters that do NOT need percent-encoding in S3 canonical URIs.
    private static let uriUnreserved: CharacterSet = {
        var cs = CharacterSet.alphanumerics
        cs.insert(charactersIn: "-._~")
        return cs
    }()

    /// Build sorted, semicolon-delimited canonical query string.
    private func buildCanonicalQueryString(url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems, !items.isEmpty else {
            return ""
        }
        let encoded: [(String, String)] = items.map { item in
            (Self.uriEncode(item.name), Self.uriEncode(item.value ?? ""))
        }
        let sorted = encoded.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }
        return sorted.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    /// URI-encode a string per AWS requirements (RFC 3986).
    private static func uriEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    /// Build canonical headers and signed headers list.
    /// Headers are lowercased, sorted by name, values trimmed.
    private func buildCanonicalHeaders(request: URLRequest) -> (canonical: String, signed: String) {
        guard let allHeaders = request.allHTTPHeaderFields else {
            return ("host:\(request.url!.host!)\n", "host")
        }

        // Include host, content-type (if present), range (if present), and all x-amz-* headers
        var headers: [(String, String)] = []
        for (key, value) in allHeaders {
            let lower = key.lowercased()
            if lower == "host" || lower == "content-type" || lower == "range" || lower.hasPrefix("x-amz-") {
                headers.append((lower, value.trimmingCharacters(in: .whitespaces)))
            }
        }
        headers.sort { $0.0 < $1.0 }

        let canonical = headers.map { "\($0.0):\($0.1)\n" }.joined()
        let signed = headers.map { $0.0 }.joined(separator: ";")
        return (canonical, signed)
    }

    /// Returns the sorted, semicolon-delimited signed headers string.
    private func signedHeaders(request: URLRequest) -> String {
        guard let allHeaders = request.allHTTPHeaderFields else { return "host" }
        var names: [String] = []
        for key in allHeaders.keys {
            let lower = key.lowercased()
            if lower == "host" || lower == "content-type" || lower == "range" || lower.hasPrefix("x-amz-") {
                names.append(lower)
            }
        }
        return names.sorted().joined(separator: ";")
    }

    /// Derive the signing key via chained HMAC-SHA256.
    /// `HMAC(HMAC(HMAC(HMAC("AWS4" + secret, date), region), service), "aws4_request")`
    private func deriveSigningKey(secret: String, dateStamp: String, region: String, service: String) throws -> Data {
        let kSecret = Data(("AWS4" + secret).utf8)
        let kDate = hmacSHA256(key: kSecret, data: Data(dateStamp.utf8))
        let kRegion = hmacSHA256(key: kDate, data: Data(region.utf8))
        let kService = hmacSHA256(key: kRegion, data: Data(service.utf8))
        let kSigning = hmacSHA256(key: kService, data: Data("aws4_request".utf8))
        return kSigning
    }

    /// Compute HMAC-SHA256 and return raw bytes as Data.
    private func hmacSHA256(key: Data, data: Data) -> Data {
        let symmetricKey = SymmetricKey(data: key)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: symmetricKey)
        return Data(mac)
    }

    // MARK: - Date Formatters

    /// ISO 8601 basic format: `yyyyMMdd'T'HHmmss'Z'`
    private static let amzDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        f.timeZone = TimeZone(abbreviation: "UTC")
        return f
    }()

    /// Date stamp: `yyyyMMdd`
    private static let dateStampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(abbreviation: "UTC")
        return f
    }()
}

// MARK: - Errors

enum S3Error: LocalizedError {
    case bucketNotFound
    case unauthorized
    case unexpectedStatus(Int)
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .bucketNotFound: return "S3 bucket not found. Check bucket name and region."
        case .unauthorized: return "S3 authentication failed. Check access key and secret."
        case .unexpectedStatus(let code): return "S3 returned HTTP \(code)"
        case .signingFailed: return "Failed to sign S3 request"
        }
    }
}

// MARK: - XML Parser for ListObjectsV2

private final class S3ListParser: NSObject, XMLParserDelegate {
    var objectCount = 0
    var totalBytes: Int64 = 0
    var isTruncated = false
    var nextContinuationToken: String?

    private var currentElement = ""
    private var currentText = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "Size" || elementName == "IsTruncated" || elementName == "NextContinuationToken" || elementName == "Key" {
            currentText = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentElement == "Size" || currentElement == "IsTruncated"
            || currentElement == "NextContinuationToken" || currentElement == "Key" {
            currentText += string
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?) {
        switch elementName {
        case "Size":
            if let size = Int64(currentText) {
                totalBytes += size
                objectCount += 1
            }
        case "IsTruncated":
            isTruncated = currentText.lowercased() == "true"
        case "NextContinuationToken":
            if !currentText.isEmpty {
                nextContinuationToken = currentText
            }
        default:
            break
        }
    }
}
