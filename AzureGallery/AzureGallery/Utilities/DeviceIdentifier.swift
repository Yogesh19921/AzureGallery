import UIKit

/// Provides a stable, short device identifier persisted in `UserDefaults`.
///
/// Generated once on first launch using `identifierForVendor` (falls back to a
/// random UUID if unavailable). The value is truncated to 8 lowercase characters
/// and reused forever on the same device. This keeps blob paths short while still
/// disambiguating devices that back up to the same Azure container.
enum DeviceIdentifier {
    private static let key = "AzureGallery.deviceId"

    /// Stable device ID persisted in UserDefaults. Generated once on first launch.
    static var current: String {
        if let existing = UserDefaults.standard.string(forKey: key) {
            return existing
        }
        // Use identifierForVendor or generate a UUID
        let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let short = String(id.prefix(8)).lowercased()
        UserDefaults.standard.set(short, forKey: key)
        return short
    }
}
