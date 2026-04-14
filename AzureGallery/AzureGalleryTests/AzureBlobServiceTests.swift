import XCTest
@testable import AzureGallery

/// Tests that AzureBlobService builds correctly-shaped signed requests.
/// Network calls (blobExists, listBlobs, validateConnection) require a live
/// Azure endpoint and are not included here — test those via integration tests.
final class AzureBlobServiceTests: XCTestCase {

    // Azurite (local emulator) well-known credentials — safe to commit.
    private static let accountName = "devstoreaccount1"
    private static let accountKeyB64 = "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="

    private var service: AzureBlobService!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let keyData = try XCTUnwrap(Data(base64Encoded: Self.accountKeyB64))
        let config = AzureConfig(
            accountName: Self.accountName,
            accountKey: keyData,
            containerName: "photos",
            endpointSuffix: "core.windows.net"
        )
        service = AzureBlobService(config: config)
    }

    // MARK: - uploadRequest shape

    func testUploadRequestUsePUT() throws {
        let req = try service.uploadRequest(blobName: "test.HEIC", contentType: "image/heic", fileSize: 1024)
        XCTAssertEqual(req.httpMethod, "PUT")
    }

    func testUploadRequestURLContainsBlobName() throws {
        let blobName = "originals/2024/01/test.HEIC"
        let req = try service.uploadRequest(blobName: blobName, contentType: "image/heic", fileSize: 1024)
        XCTAssertTrue(req.url?.absoluteString.contains("originals/2024/01/test.HEIC") == true)
    }

    func testUploadRequestHasBlobTypeBlockBlob() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-ms-blob-type"), "BlockBlob")
    }

    func testUploadRequestOmitsAccessTierByDefault() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        XCTAssertNil(req.value(forHTTPHeaderField: "x-ms-access-tier"))
    }

    func testUploadRequestIncludesAccessTierWhenProvided() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1, accessTier: "Cool")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-ms-access-tier"), "Cool")
    }

    func testUploadRequestWithTierIsSignedCorrectly() throws {
        // The tier header is x-ms-*, so it MUST be included in the HMAC signature.
        // Verify the Authorization header exists (signing didn't throw).
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1, accessTier: "Hot")
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.hasPrefix("SharedKey "))
    }

    func testApiVersionIs2024() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-ms-version"), "2024-11-04")
    }

    func testUploadRequestAuthorizationHeaderUsesSharedKey() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(auth.hasPrefix("SharedKey \(Self.accountName):"))
    }

    func testUploadRequestAuthorizationSignatureIsBase64() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        let auth = try XCTUnwrap(req.value(forHTTPHeaderField: "Authorization"))
        // Format: "SharedKey accountName:<base64-signature>"
        let signature = auth.components(separatedBy: ":").last ?? ""
        XCTAssertNotNil(Data(base64Encoded: signature), "Signature must be valid base64")
    }

    func testUploadRequestHasDateHeader() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        XCTAssertNotNil(req.value(forHTTPHeaderField: "x-ms-date"))
    }

    func testUploadRequestHasVersionHeader() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        XCTAssertNotNil(req.value(forHTTPHeaderField: "x-ms-version"))
    }

    func testUploadRequestContentLengthMatchesInput() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 99_999)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Length"), "99999")
    }

    func testUploadRequestContentTypeIsPreserved() throws {
        let req = try service.uploadRequest(blobName: "f.MOV", contentType: "video/quicktime", fileSize: 1)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "video/quicktime")
    }

    // Signing two requests with the same inputs but different dates should produce
    // different signatures (date is embedded in the string-to-sign).
    func testDifferentDatesProduceDifferentSignatures() throws {
        let r1 = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        // Wait 1 second so x-ms-date changes
        Thread.sleep(forTimeInterval: 1.1)
        let r2 = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1)
        XCTAssertNotEqual(
            r1.value(forHTTPHeaderField: "Authorization"),
            r2.value(forHTTPHeaderField: "Authorization")
        )
    }

    // MARK: - 403 regression: no x-ms-* headers added after signing

    /// Regression test for the bug where `x-ms-client-request-id` was stamped onto the
    /// request after `sign()` ran. Azure includes ALL x-ms-* headers when verifying the
    /// HMAC-SHA256 signature — an unsigned x-ms-* header produces a 403.
    ///
    /// The fix: `uploadRequest` must return a fully-signed, immutable request.
    /// Callers must NOT mutate any x-ms-* header after this point.
    func testUploadRequestHasNoClientRequestIdHeader() throws {
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 1024)
        XCTAssertNil(
            req.value(forHTTPHeaderField: "x-ms-client-request-id"),
            "x-ms-client-request-id must not be set — adding any x-ms-* header post-sign breaks the HMAC signature"
        )
    }

    func testUploadRequestSignedHeadersMatchCanonicalizedHeaders() throws {
        // Every x-ms-* header present in the request must be covered by the Authorization
        // signature. Verify by confirming the Authorization header exists and was built from
        // exactly the headers present (i.e., no stray x-ms-* headers were added afterwards).
        let req = try service.uploadRequest(blobName: "f.HEIC", contentType: "image/heic", fileSize: 512)
        let xmsHeaders = req.allHTTPHeaderFields?
            .keys
            .filter { $0.lowercased().hasPrefix("x-ms-") }
            .sorted() ?? []

        // The only x-ms-* headers uploadRequest should set are: x-ms-date, x-ms-version,
        // x-ms-blob-type. All three must be present and signed.
        let expected: Set<String> = ["x-ms-date", "x-ms-version", "x-ms-blob-type"]
        XCTAssertEqual(Set(xmsHeaders.map { $0.lowercased() }), expected,
                       "Unexpected x-ms-* headers found — any addition after sign() will break auth")
    }

    // MARK: - AzureError descriptions

    func testErrorDescriptionsAreNonEmpty() {
        let errors: [AzureError] = [.containerNotFound, .unauthorized, .signingFailed, .unexpectedStatus(503)]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "\(error) must have a description")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testUnexpectedStatusDescriptionContainsCode() {
        XCTAssertTrue(AzureError.unexpectedStatus(429).errorDescription?.contains("429") == true)
    }
}
