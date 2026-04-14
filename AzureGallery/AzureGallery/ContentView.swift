import SwiftUI

struct ContentView: View {
    private let engine = BackupEngine.shared

    @State private var showLogShare = false

    /// Computes overall upload progress (0...1) from all active upload items.
    private var overallProgress: Double {
        let items = Array(engine.activeUploadItems.values)
        guard !items.isEmpty else { return 0 }
        let totalBytes = items.reduce(Int64(0)) { $0 + $1.totalBytes }
        guard totalBytes > 0 else { return 0 }
        let sentBytes = items.reduce(Int64(0)) { $0 + $1.bytesSent }
        return Double(sentBytes) / Double(totalBytes)
    }

    var body: some View {
        TabView {
            GalleryView()
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }

            AlbumsView()
                .tabItem { Label("Albums", systemImage: "rectangle.stack") }

            SearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }

            BackupStatusView()
                .tabItem {
                    if engine.activeUploads > 0 {
                        Label {
                            Text("Backup")
                        } icon: {
                            Image(uiImage: circularProgressImage(progress: overallProgress))
                                .renderingMode(.template)
                        }
                    } else {
                        Label("Backup", systemImage: "cloud.fill")
                    }
                }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
        .overlay {
            // Hidden image that forces SwiftUI to re-render the tab icon when progress changes
            if engine.activeUploads > 0 {
                BackupTabProgressUpdater(progress: overallProgress)
                    .frame(width: 0, height: 0)
                    .hidden()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .deviceDidShake)) { _ in
            showLogShare = true
        }
        .sheet(isPresented: $showLogShare) {
            NavigationStack {
                LogShareSheet()
            }
        }
    }
}

// MARK: - Backup Tab Progress Updater

/// Renders a circular progress UIImage and injects it as a named image resource
/// for the tab bar. SwiftUI tab items only accept `Label`/`Text`/`Image`, so we
/// render a UIImage with Core Graphics and use it via `Image(uiImage:)`.
///
/// In practice, SwiftUI's `.tabItem` does not re-render custom images dynamically
/// from `Image(uiImage:)` without workarounds. Instead we use a simpler approach:
/// show the progress in the Backup tab overlay rather than replacing the icon.
private struct BackupTabProgressUpdater: View {
    let progress: Double

    var body: some View {
        // This view exists to observe progress changes and trigger re-renders.
        // The actual progress image is drawn as an overlay on the tab content.
        Image(uiImage: circularProgressImage(progress: progress))
            .resizable()
            .frame(width: 25, height: 25)
    }
}

// MARK: - Log Share Sheet

private struct LogShareSheet: View {
    @Environment(\.dismiss) private var dismiss

    private var logText: String {
        AppLogger.shared.exportText()
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Diagnostic Logs")
                .font(.headline)

            ScrollView {
                Text(logText.isEmpty ? "No logs available." : logText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            .background(Color(.systemGroupedBackground))
            .cornerRadius(12)

            ShareLink(item: logText.isEmpty ? "No logs available." : logText) {
                Label("Share Logs", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }
}
