import SwiftUI

struct ContentView: View {
    let stats: BackupStats

    var body: some View {
        TabView {
            GalleryView()
                .tabItem { Label("Gallery", systemImage: "photo.on.rectangle") }

            AlbumsView()
                .tabItem { Label("Albums", systemImage: "rectangle.stack") }

            BackupStatusView(stats: stats)
                .tabItem { Label("Backup", systemImage: "cloud.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
        }
    }
}
