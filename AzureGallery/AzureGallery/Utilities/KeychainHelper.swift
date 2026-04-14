import Foundation
import Security

/// Thin wrapper around the iOS Keychain for storing and retrieving string values.
///
/// All items are stored as `kSecClassGenericPassword` with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — they are not backed up to iCloud
/// and are locked when the device is locked.
enum KeychainHelper {
    private static let service = "com.yogesh.AzureGallery"

    /// Persist `value` under `key`, replacing any existing entry.
    static func save(_ value: String, key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            // AfterFirstUnlock: device-only (not synced to iCloud), but readable in
            // background — needed because BackupEngine accesses the key during background
            // URLSession events when the screen may be locked.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// Retrieve the string stored under `key`, or `nil` if no item exists.
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Remove the Keychain item for `key`. No-op if the item does not exist.
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Keychain key constants used throughout the app.
extension KeychainHelper {
    static let connectionStringKey = "azureConnectionString"
    static let containerNameKey = "azureContainerName"
}
