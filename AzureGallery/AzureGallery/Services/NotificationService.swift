import Foundation
import UserNotifications
import UIKit

/// Handles local notifications for backup progress and badge management.
/// All methods are static — there is no shared state.
enum NotificationService {

    /// Requests notification permission from the user. Call once on first launch.
    @MainActor
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
            }
        }
    }

    /// Posts a local notification when a batch of uploads completes.
    static func postBatchComplete(uploadedCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Backup Complete"
        content.body = "\(uploadedCount) photos backed up"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "batchComplete-\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Updates the app icon badge count.
    static func updateBadge(count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
    }
}
