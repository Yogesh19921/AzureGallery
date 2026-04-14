import XCTest
@testable import AzureGallery

/// Tests that GCPBlobService builds correctly-shaped signed requests using
/// AWS Signature V4 adapted for GCS HMAC key authentication.
///
/// Network calls (validate, blobExists, containerStats) require a live GCS
/// endpoint and are not included here — test those via integration tests.
final class GCPBlobServiceTests: XCTestCase {

    // GCS documentation example HMAC credentials — safe to commit.
    private static let accessKey = "GOOGTS7C7FUP3AIRVJTE2BCDKINBTES3HC2GY5CBFJDCQ2SYHV6A6XXVTJFSA"
    private static let secretB64 = "bGoa+V7g/yqDXvKRqq+JTFn4uQZbPiQJo4pf9RzJ"

    private var service: GCPBlobService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // The HMAC secret from GCS is base64-encoded; decode to raw bytes.
        let secretData = try XCTUnwrap(Data(base64Encoded: Self.secretB64))
        let config = GCPConfig(
            accessKey: Self.accessKey,
            secret: secretData,
            bucket: "test-photos",
            projectId: "my-project-123"
        )
        service = GCPBlobService(config: config)
    }

    // MARK: - Authorization header format

    func testAuthorizationHeaderStartsWithAWS4HMACSHA256() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256"), "Authorization must start with AWS4-HMAC-SHA256")
    }

    func testAuthorizationHeaderContainsCredentialField() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.contains("Credential="), "Authorization must contain Credential=")
    }

    func testAuthorizationHeaderContainsSignedHeadersField() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.contains("SignedHeaders="), "Authorization must contain SignedHeaders=")
    }

    func testAuthorizationHeaderContainsSignatureField() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.contains("Signature="), "Authorization must contain Signature=")
    }

    // MARK: - URL format (path-style)

    func testURLIsPathStyle() throws {
        let req = try service.uploadRequest(blobName: "originals/2024/01/photo.HEIC", contentType: "image/heic", fileSize: 512)
        let url = try XCTUnwrap(req.url)
        XCTAssertEqual(url.host, "storage.googleapis.com")
        XCTAssertTrue(url.path.hasPrefix("/test-photos/"), "URL path must start with /<bucket>/")
    }

    func testURLContainsBlobName() throws {
        let blobName = "originals/2024/01/photo.HEIC"
        let req = try service.uploadRequest(blobName: blobName, contentType: "image/heic", fileSize: 512)
        let url = try XCTUnwrap(req.url)
        XCTAssertTrue(url.absoluteString.contains("originals/2024/01/photo.HEIC"))
    }

    func testObjectURLFormat() {
        let url = service.config.objectURL(key: "originals/2024/01/photo.HEIC")
        XCTAssertEqual(url.absoluteString, "https://storage.googleapis.com/test-photos/originals/2024/01/photo.HEIC")
    }

    func testBucketURLFormat() {
        let url = service.config.bucketURL()
        XCTAssertEqual(url.absoluteString, "https://storage.googleapis.com/test-photos")
    }

    // MARK: - Credential scope uses "auto" region and "s3" service

    func testCredentialScopeUsesAutoRegionAndS3Service() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))

        // Extract the Credential value: access_key/YYYYMMDD/auto/s3/aws4_request
        guard let credentialRange = auth.range(of: "Credential=") else {
            XCTFail("No Credential= in Authorization header")
            return
        }
        let afterCredential = auth[credentialRange.upperBound...]
        let credentialEnd = afterCredential.firstIndex(of: ",") ?? afterCredential.endIndex
        let credential = String(afterCredential[..<credentialEnd])

        // Credential format: accessKey/YYYYMMDD/region/service/aws4_request
        let parts = credential.components(separatedBy: "/")
        XCTAssertEqual(parts.count, 5, "Credential scope must have 5 parts")
        XCTAssertEqual(parts[0], Self.accessKey)
        XCTAssertEqual(parts[2], "auto", "Region must be 'auto' for GCS HMAC")
        XCTAssertEqual(parts[3], "s3", "Service must be 's3' for GCS HMAC")
        XCTAssertEqual(parts[4], "aws4_request")
    }

    // MARK: - Required headers

    func testUploadRequestHasHostHeader() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Host"), "storage.googleapis.com")
    }

    func testUploadRequestHasAmzContentSha256Header() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-amz-content-sha256"), "UNSIGNED-PAYLOAD")
    }

    func testUploadRequestHasAmzDateHeader() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        let amzDate = try XCTUnwrap(req.value(forHTTPHeaderField: "x-amz-date"))
        // Format: YYYYMMDDTHHmmssZ (16 characters)
        XCTAssertEqual(amzDate.count, 16, "x-amz-date must be in ISO 8601 basic format")
        XCTAssertTrue(amzDate.hasSuffix("Z"), "x-amz-date must end with Z")
        XCTAssertTrue(amzDate.contains("T"), "x-amz-date must contain T separator")
    }

    func testUploadRequestUsePUT() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        XCTAssertEqual(req.httpMethod, "PUT")
    }

    func testUploadRequestContentTypePreserved() throws {
        let req = try service.uploadRequest(blobName: "test.MOV", contentType: "video/quicktime", fileSize: 999)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "video/quicktime")
    }

    func testUploadRequestContentLengthMatchesInput() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 88_888)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Length"), "88888")
    }

    // MARK: - Storage class mapping

    func testStorageClassNilMapsToSTANDARD() {
        XCTAssertEqual(GCPBlobService.gcsStorageClass(from: nil), "STANDARD")
    }

    func testStorageClassHotMapsToSTANDARD() {
        XCTAssertEqual(GCPBlobService.gcsStorageClass(from: "Hot"), "STANDARD")
    }

    func testStorageClassCoolMapsToNEARLINE() {
        XCTAssertEqual(GCPBlobService.gcsStorageClass(from: "Cool"), "NEARLINE")
    }

    func testStorageClassColdMapsToCOLDLINE() {
        XCTAssertEqual(GCPBlobService.gcsStorageClass(from: "Cold"), "COLDLINE")
    }

    func testStorageClassArchiveMapsToARCHIVE() {
        XCTAssertEqual(GCPBlobService.gcsStorageClass(from: "Archive"), "ARCHIVE")
    }

    func testUploadRequestOmitsStorageClassForStandard() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024, accessTier: nil)
        XCTAssertNil(req.value(forHTTPHeaderField: "x-goog-storage-class"),
                     "STANDARD storage class should not set the header (it's the default)")
    }

    func testUploadRequestSetsStorageClassForCool() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024, accessTier: "Cool")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-storage-class"), "NEARLINE")
    }

    func testUploadRequestSetsStorageClassForCold() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024, accessTier: "Cold")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-storage-class"), "COLDLINE")
    }

    func testUploadRequestSetsStorageClassForArchive() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024, accessTier: "Archive")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-goog-storage-class"), "ARCHIVE")
    }

    // MARK: - HEAD request for blobExists

    func testBlobExistsUsesHEADMethod() throws {
        // We can only verify the request shape, not the actual network call.
        // Build a request the same way blobExists does internally.
        let url = service.config.objectURL(key: "test.HEIC")
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("storage.googleapis.com", forHTTPHeaderField: "Host")
        request.setValue("UNSIGNED-PAYLOAD", forHTTPHeaderField: "x-amz-content-sha256")
        try service.signV4(&request, httpMethod: "HEAD")

        XCTAssertEqual(request.httpMethod, "HEAD")
        let auth = try XCTUnwrap(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.hasPrefix("AWS4-HMAC-SHA256"))
    }

    // MARK: - Signing helpers

    func testDateStampFormat() {
        // A known date
        let date = Date(timeIntervalSince1970: 1700000000) // 2023-11-14T22:13:20Z
        let stamp = GCPBlobService.dateStamp(date)
        XCTAssertEqual(stamp, "20231114")
    }

    func testAmzDateFormat() {
        let date = Date(timeIntervalSince1970: 1700000000) // 2023-11-14T22:13:20Z
        let amz = GCPBlobService.amzDate(date)
        XCTAssertEqual(amz, "20231114T221320Z")
    }

    func testDeriveSigningKeyProducesNonEmptyData() throws {
        let secret = Data("testSecret".utf8)
        let key = try GCPBlobService.deriveSigningKey(secret: secret, dateStamp: "20240101", region: "auto", service: "s3")
        XCTAssertFalse(key.isEmpty)
        XCTAssertEqual(key.count, 32, "HMAC-SHA256 output must be 32 bytes")
    }

    // MARK: - GCPError descriptions

    func testErrorDescriptionsAreNonEmpty() {
        let errors: [GCPError] = [.bucketNotFound, .unauthorized, .signingFailed, .unexpectedStatus(503)]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) must have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testUnexpectedStatusDescriptionContainsCode() {
        XCTAssertTrue(GCPError.unexpectedStatus(429).errorDescription?.contains("429") == true)
    }

    // MARK: - GCPConfig

    func testGCPConfigObjectURL() {
        let secretData = Data(base64Encoded: Self.secretB64)!
        let config = GCPConfig(accessKey: "key", secret: secretData, bucket: "mybucket", projectId: "")
        let url = config.objectURL(key: "path/to/object.jpg")
        XCTAssertEqual(url.absoluteString, "https://storage.googleapis.com/mybucket/path/to/object.jpg")
    }

    func testGCPConfigBucketURL() {
        let secretData = Data(base64Encoded: Self.secretB64)!
        let config = GCPConfig(accessKey: "key", secret: secretData, bucket: "mybucket", projectId: "")
        let url = config.bucketURL()
        XCTAssertEqual(url.absoluteString, "https://storage.googleapis.com/mybucket")
    }
}
