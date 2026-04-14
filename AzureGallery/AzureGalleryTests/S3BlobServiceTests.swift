import XCTest
@testable import AzureGallery

/// Tests that S3BlobService builds correctly-shaped signed requests using AWS Signature V4.
/// Network calls (blobExists, downloadBlob, validate) require a live S3 endpoint and are
/// not included here — test those via integration tests.
///
/// Credentials below are the AWS-published example credentials (safe to commit):
/// https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
final class S3BlobServiceTests: XCTestCase {

    private static let accessKeyId = "AKIAIOSFODNN7EXAMPLE"
    private static let secretAccessKey = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    private static let bucket = "examplebucket"
    private static let region = "us-east-1"

    private var service: S3BlobService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let config = S3Config(
            accessKeyId: Self.accessKeyId,
            secretAccessKey: Self.secretAccessKey,
            bucket: Self.bucket,
            region: Self.region
        )
        service = S3BlobService(config: config)
    }

    // MARK: - Authorization header format

    func testUploadRequestAuthorizationHeaderUsesAWS4HMACSHA256() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256 "), "Authorization must start with AWS4-HMAC-SHA256")
    }

    func testUploadRequestAuthorizationContainsCredential() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.contains("Credential=\(Self.accessKeyId)/"), "Authorization must contain Credential=<accessKeyId>/")
    }

    func testUploadRequestAuthorizationContainsSignedHeaders() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.contains("SignedHeaders="), "Authorization must contain SignedHeaders=")
    }

    func testUploadRequestAuthorizationContainsSignature() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.contains("Signature="), "Authorization must contain Signature=")
    }

    func testUploadRequestAuthorizationSignatureIsHex() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        // Extract the hex signature after "Signature="
        let signaturePrefix = "Signature="
        guard let range = auth.range(of: signaturePrefix) else {
            XCTFail("Missing Signature= in Authorization header")
            return
        }
        let signature = String(auth[range.upperBound...])
        // SHA-256 HMAC produces 64 hex chars
        XCTAssertEqual(signature.count, 64, "Signature must be 64 hex characters (SHA-256)")
        XCTAssertTrue(signature.allSatisfy { $0.isHexDigit }, "Signature must be valid hex")
    }

    func testUploadRequestAuthorizationScopeContainsRegionAndS3() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.contains("/\(Self.region)/s3/aws4_request"), "Scope must contain region/s3/aws4_request")
    }

    // MARK: - Required headers

    func testUploadRequestHasHostHeader() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let host = try XCTUnwrap(req.value(forHTTPHeaderField: "Host"))
        XCTAssertEqual(host, "\(Self.bucket).s3.\(Self.region).amazonaws.com")
    }

    func testUploadRequestHasAmzContentSha256Header() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let hash = try XCTUnwrap(req.value(forHTTPHeaderField: "x-amz-content-sha256"))
        XCTAssertEqual(hash, "UNSIGNED-PAYLOAD", "Upload requests must use UNSIGNED-PAYLOAD for background uploads")
    }

    func testUploadRequestHasAmzDateHeader() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let date = try XCTUnwrap(req.value(forHTTPHeaderField: "x-amz-date"))
        // Format: yyyyMMdd'T'HHmmss'Z' — e.g. 20240101T120000Z
        let regex = try NSRegularExpression(pattern: "^\\d{8}T\\d{6}Z$")
        let range = NSRange(date.startIndex..<date.endIndex, in: date)
        XCTAssertNotNil(regex.firstMatch(in: date, range: range), "x-amz-date must be in ISO 8601 basic format")
    }

    func testUploadRequestHasAuthorizationHeader() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        XCTAssertNotNil(req.value(forHTTPHeaderField: "Authorization"))
    }

    func testUploadRequestContentTypeIsPreserved() throws {
        let req = try service.uploadRequest(blobName: "f.MOV", contentType: "video/quicktime", fileSize: 1)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "video/quicktime")
    }

    func testUploadRequestContentLengthMatchesInput() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 99_999)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Length"), "99999")
    }

    // MARK: - Virtual-hosted-style URL

    func testUploadRequestUsesVirtualHostedStyleURL() throws {
        let req = try service.uploadRequest(blobName: "originals/2024/01/test.HEIC", contentType: "image/heic", fileSize: 1024)
        let url = try XCTUnwrap(req.url)
        XCTAssertEqual(url.host, "\(Self.bucket).s3.\(Self.region).amazonaws.com",
                       "URL must use virtual-hosted-style: <bucket>.s3.<region>.amazonaws.com")
    }

    func testUploadRequestURLContainsObjectKey() throws {
        let blobName = "originals/2024/01/test.HEIC"
        let req = try service.uploadRequest(blobName: blobName, contentType: "image/heic", fileSize: 1024)
        let url = try XCTUnwrap(req.url)
        XCTAssertTrue(url.absoluteString.contains("originals/2024/01/test.HEIC"))
    }

    func testObjectURLFormat() {
        let config = S3Config(accessKeyId: "AK", secretAccessKey: "SK", bucket: "mybucket", region: "us-east-1")
        let url = config.objectURL(key: "photos/test.jpg")
        XCTAssertEqual(url.absoluteString, "https://mybucket.s3.us-east-1.amazonaws.com/photos/test.jpg")
    }

    // MARK: - HTTP method

    func testUploadRequestIsPUT() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        XCTAssertEqual(req.httpMethod, "PUT")
    }

    // MARK: - Storage class mapping

    func testStorageClassMappingHot() {
        XCTAssertEqual(S3BlobService.storageClass(forTier: "Hot"), "STANDARD")
    }

    func testStorageClassMappingCool() {
        XCTAssertEqual(S3BlobService.storageClass(forTier: "Cool"), "STANDARD_IA")
    }

    func testStorageClassMappingCold() {
        XCTAssertEqual(S3BlobService.storageClass(forTier: "Cold"), "GLACIER_IR")
    }

    func testStorageClassMappingArchive() {
        XCTAssertEqual(S3BlobService.storageClass(forTier: "Archive"), "DEEP_ARCHIVE")
    }

    func testStorageClassMappingUnknownReturnsNil() {
        XCTAssertNil(S3BlobService.storageClass(forTier: "Unknown"))
    }

    func testUploadRequestIncludesStorageClassWhenTierProvided() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1, accessTier: "Cool")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-amz-storage-class"), "STANDARD_IA")
    }

    func testUploadRequestOmitsStorageClassByDefault() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        XCTAssertNil(req.value(forHTTPHeaderField: "x-amz-storage-class"))
    }

    func testUploadRequestOmitsStorageClassForUnknownTier() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1, accessTier: "Nonexistent")
        XCTAssertNil(req.value(forHTTPHeaderField: "x-amz-storage-class"))
    }

    // MARK: - S3Error descriptions

    func testErrorDescriptionsAreNonEmpty() {
        let errors: [S3Error] = [.bucketNotFound, .unauthorized, .signingFailed, .unexpectedStatus(503)]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) must have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testUnexpectedStatusDescriptionContainsCode() {
        XCTAssertTrue(S3Error.unexpectedStatus(429).errorDescription?.contains("429") == true)
    }

    // MARK: - S3Config

    func testS3ConfigEndpoint() {
        let config = S3Config(accessKeyId: "AK", secretAccessKey: "SK", bucket: "mybucket", region: "eu-west-1")
        XCTAssertEqual(config.endpoint, "https://mybucket.s3.eu-west-1.amazonaws.com")
    }

    func testS3ConfigBucketURL() {
        let config = S3Config(accessKeyId: "AK", secretAccessKey: "SK", bucket: "mybucket", region: "us-west-2")
        XCTAssertEqual(config.bucketURL().absoluteString, "https://mybucket.s3.us-west-2.amazonaws.com")
    }

    // MARK: - Signature determinism

    func testSameInputsProduceSameSignature() throws {
        // Two requests built at the same instant should have the same Authorization header.
        // We can't easily freeze time, but two rapid calls should produce the same date.
        let r1 = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 100)
        let r2 = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 100)
        // If they happen within the same second, signatures should match
        let date1 = r1.value(forHTTPHeaderField: "x-amz-date")
        let date2 = r2.value(forHTTPHeaderField: "x-amz-date")
        if date1 == date2 {
            XCTAssertEqual(r1.value(forHTTPHeaderField: "Authorization"),
                           r2.value(forHTTPHeaderField: "Authorization"),
                           "Same inputs + same timestamp must produce the same signature")
        }
    }

    // MARK: - Provider name

    func testProviderName() {
        XCTAssertEqual(service.providerName, "Amazon S3")
    }
}
