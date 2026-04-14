import SwiftUI

// MARK: - Appearance

/// User-selectable appearance override. Defaults to `.system` (follows iOS setting).
enum AppearanceMode: String, CaseIterable {
    case system = "System"
    case light  = "Light"
    case dark   = "Dark"

    /// Maps to SwiftUI's `ColorScheme?` — nil means "follow the system".
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - App Delegate (needed for background URLSession events)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        BackupEngine.shared.handleBackgroundSessionEvents(completionHandler: completionHandler)
    }
}

// MARK: - App Entry Point
@main
struct AzureGalleryApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @State private var photoLibrary = PhotoLibraryService()

    /// Persisted appearance preference. Defaults to "System" on first launch.
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(photoLibrary)
                // nil = follow iOS system setting; .light/.dark = override
                .preferredColorScheme(appearanceMode.colorScheme)
                .task {
                    do {
                        try DatabaseService.shared.setup()
                    } catch {
                        print("DB setup failed: \(error)")
                    }
                    await photoLibrary.requestAuthorization()
                    NotificationService.requestPermission()
                    await BackupEngine.shared.start(photoLibrary: photoLibrary)
                }
        }
    }
}
