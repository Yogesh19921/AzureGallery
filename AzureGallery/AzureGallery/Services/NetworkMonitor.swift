import Foundation
import Network
import Observation

/// Observes device network connectivity via `NWPathMonitor`.
///
/// Properties are published on the main actor so SwiftUI views and `@Observable`
/// services can read them safely. The monitor runs on a dedicated serial queue
/// and is started eagerly in `init()`.
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected: Bool = true
    private(set) var isCellular: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.yogesh.AzureGallery.NetworkMonitor")

    /// Callback invoked on the main actor whenever the path changes.
    /// `BackupEngine` sets this to auto-resume uploads when Wi-Fi becomes available.
    var onPathChange: (() -> Void)?

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let connected = path.status == .satisfied
            let cellular = path.usesInterfaceType(.cellular)
            DispatchQueue.main.async {
                self.isConnected = connected
                self.isCellular = cellular
                self.onPathChange?()
            }
        }
        monitor.start(queue: queue)
    }
}
