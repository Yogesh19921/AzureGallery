import XCTest
@testable import AzureGallery

/// Tests for KeychainHelper.
///
/// **Requirement:** The app must be code-signed (Developer certificate) for Keychain tests
/// to pass. When the app target is built without code signing (e.g. bare `xcodebuild`
/// without a team), `SecItemAdd` returns `errSecMissingEntitlement` and tests that write
/// to the Keychain are automatically skipped. Run them from Xcode or with
/// `CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=<TeamID>` to exercise the full suite.
final class KeychainHelperTests: XCTestCase {

    // Use a dedicated test key that won't collide with real app data
    private let testKey = "com.yogesh.AzureGallery.unit-test-key"

    // MARK: - Keychain availability check

    /// Returns true if the Keychain is accessible in this build/environment.
    private var keychainAvailable: Bool {
        let probe = "probe"
        KeychainHelper.save(probe, key: testKey + ".probe")
        let ok = KeychainHelper.load(key: testKey + ".probe") == probe
        KeychainHelper.delete(key: testKey + ".probe")
        return ok
    }

    override func tearDown() {
        super.tearDown()
        // Always clean up so tests don't bleed state into one another
        KeychainHelper.delete(key: testKey)
    }

    // MARK: - Save & Load

    func testSaveAndLoadRoundTrip() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain unavailable — build without code signing")
        KeychainHelper.save("hello-world", key: testKey)
        XCTAssertEqual(KeychainHelper.load(key: testKey), "hello-world")
    }

    func testLoadMissingKeyReturnsNil() {
        XCTAssertNil(KeychainHelper.load(key: testKey))
    }

    func testOverwriteUpdatesToLatestValue() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain unavailable — build without code signing")
        KeychainHelper.save("first", key: testKey)
        KeychainHelper.save("second", key: testKey)
        XCTAssertEqual(KeychainHelper.load(key: testKey), "second")
    }

    func testSavesUnicodeStrings() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain unavailable — build without code signing")
        let value = "連接字符串-テスト-🔑"
        KeychainHelper.save(value, key: testKey)
        XCTAssertEqual(KeychainHelper.load(key: testKey), value)
    }

    func testSavesLongConnectionString() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain unavailable — build without code signing")
        // Real Azure connection strings can be 200+ characters
        let longValue = "DefaultEndpointsProtocol=https;AccountName=myaccount;AccountKey=" + String(repeating: "A", count: 88) + "==;EndpointSuffix=core.windows.net"
        KeychainHelper.save(longValue, key: testKey)
        XCTAssertEqual(KeychainHelper.load(key: testKey), longValue)
    }

    // MARK: - Delete

    func testDeleteRemovesValue() throws {
        try XCTSkipUnless(keychainAvailable, "Keychain unavailable — build without code signing")
        KeychainHelper.save("to-delete", key: testKey)
        KeychainHelper.delete(key: testKey)
        XCTAssertNil(KeychainHelper.load(key: testKey))
    }

    func testDeleteNonExistentKeyIsNoOp() {
        // Should not crash (no Keychain access needed — delete on missing item is a no-op)
        KeychainHelper.delete(key: testKey)
    }

    // MARK: - Key constants

    func testConnectionStringKeyConstant() {
        XCTAssertEqual(KeychainHelper.connectionStringKey, "azureConnectionString")
    }

    func testContainerNameKeyConstant() {
        XCTAssertEqual(KeychainHelper.containerNameKey, "azureContainerName")
    }
}
