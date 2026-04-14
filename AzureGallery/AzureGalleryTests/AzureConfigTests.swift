import XCTest
@testable import AzureGallery

final class AzureConfigTests: XCTestCase {

    // MARK: - Parsing: happy path

    func testParseValidConnectionString() throws {
        let key = Data(repeating: 0xFF, count: 32).base64EncodedString()
        let cs = "DefaultEndpointsProtocol=https;AccountName=myaccount;AccountKey=\(key);EndpointSuffix=core.windows.net"
        let config = try AzureConfig.parse(connectionString: cs, containerName: "photos")
        XCTAssertEqual(config.accountName, "myaccount")
        XCTAssertEqual(config.accountKey, Data(repeating: 0xFF, count: 32))
        XCTAssertEqual(config.containerName, "photos")
        XCTAssertEqual(config.endpointSuffix, "core.windows.net")
    }

    func testParseAccountKeyWithBase64Padding() throws {
        // Real Azure keys are 64-byte values; padding characters ('=') appear at the end.
        // The parser splits on the first '=' to avoid truncating the key.
        let rawKey = Data([0x00, 0x01, 0x02, 0x03, 0x04])
        let encoded = rawKey.base64EncodedString()          // "AAECAwQ="
        let cs = "AccountName=acct;AccountKey=\(encoded)"
        let config = try AzureConfig.parse(connectionString: cs, containerName: "c")
        XCTAssertEqual(config.accountKey, rawKey)
    }

    // MARK: - Parsing: missing fields

    func testParseMissingAccountNameThrows() {
        let key = Data(repeating: 0, count: 32).base64EncodedString()
        XCTAssertThrowsError(try AzureConfig.parse(connectionString: "AccountKey=\(key)", containerName: "c")) { error in
            guard case AzureConfig.ParseError.missingField(let f) = error else { return XCTFail("wrong error") }
            XCTAssertEqual(f, "AccountName")
        }
    }

    func testParseMissingAccountKeyThrows() {
        XCTAssertThrowsError(try AzureConfig.parse(connectionString: "AccountName=acct", containerName: "c")) { error in
            guard case AzureConfig.ParseError.missingField(let f) = error else { return XCTFail("wrong error") }
            XCTAssertEqual(f, "AccountKey")
        }
    }

    func testParseInvalidBase64KeyThrows() {
        let cs = "AccountName=acct;AccountKey=!!!notbase64!!!"
        XCTAssertThrowsError(try AzureConfig.parse(connectionString: cs, containerName: "c")) { error in
            XCTAssertEqual(error as? AzureConfig.ParseError, .invalidBase64Key)
        }
    }

    // MARK: - Parsing: defaults

    func testParseDefaultsEndpointSuffixWhenAbsent() throws {
        let key = Data(repeating: 0, count: 32).base64EncodedString()
        let config = try AzureConfig.parse(connectionString: "AccountName=a;AccountKey=\(key)", containerName: "c")
        XCTAssertEqual(config.endpointSuffix, "core.windows.net")
    }

    func testParseCustomEndpointSuffix() throws {
        let key = Data(repeating: 0, count: 32).base64EncodedString()
        let cs = "AccountName=a;AccountKey=\(key);EndpointSuffix=core.chinacloudapi.cn"
        let config = try AzureConfig.parse(connectionString: cs, containerName: "c")
        XCTAssertEqual(config.endpointSuffix, "core.chinacloudapi.cn")
    }

    func testParseEmptyContainerNameDefaultsToPhotos() throws {
        let key = Data(repeating: 0, count: 32).base64EncodedString()
        let config = try AzureConfig.parse(connectionString: "AccountName=a;AccountKey=\(key)", containerName: "")
        XCTAssertEqual(config.containerName, "photos")
    }

    // MARK: - URL helpers

    func testBlobEndpointFormat() throws {
        let config = try makeConfig(account: "myaccount", suffix: "core.windows.net")
        XCTAssertEqual(config.blobEndpoint, "https://myaccount.blob.core.windows.net")
    }

    func testBlobURLBuildsCorrectPath() throws {
        let config = try makeConfig(account: "acct", suffix: "core.windows.net", container: "photos")
        let url = config.blobURL(blobName: "originals/2024/01/test.HEIC")
        XCTAssertEqual(url.absoluteString, "https://acct.blob.core.windows.net/photos/originals/2024/01/test.HEIC")
    }

    func testBlobURLPercentEncodesSpaces() throws {
        let config = try makeConfig()
        let url = config.blobURL(blobName: "originals/with spaces/file.HEIC")
        XCTAssertTrue(url.absoluteString.contains("%20"), "Spaces in blob names must be percent-encoded")
    }

    func testContainerURL() throws {
        let config = try makeConfig(account: "acct", suffix: "core.windows.net", container: "photos")
        XCTAssertEqual(config.containerURL().absoluteString, "https://acct.blob.core.windows.net/photos")
    }

    // MARK: - Error descriptions

    func testParseErrorDescriptionsAreNonNil() {
        XCTAssertNotNil(AzureConfig.ParseError.missingField("X").errorDescription)
        XCTAssertNotNil(AzureConfig.ParseError.invalidBase64Key.errorDescription)
    }

    // MARK: - Helpers

    private func makeConfig(account: String = "acct",
                            suffix: String = "core.windows.net",
                            container: String = "photos") throws -> AzureConfig {
        let key = Data(repeating: 0, count: 32).base64EncodedString()
        return try AzureConfig.parse(
            connectionString: "AccountName=\(account);AccountKey=\(key);EndpointSuffix=\(suffix)",
            containerName: container
        )
    }
}

extension AzureConfig.ParseError: Equatable {
    public static func == (lhs: AzureConfig.ParseError, rhs: AzureConfig.ParseError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidBase64Key, .invalidBase64Key): return true
        case (.missingField(let a), .missingField(let b)): return a == b
        default: return false
        }
    }
}
