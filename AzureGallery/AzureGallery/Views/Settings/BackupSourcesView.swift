import SwiftUI

struct BackupSourcesView: View {
    @State private var selection = BackupSelectionService.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: $selection.backupAllPhotos) {
                    Label("All Photos", systemImage: "photo.on.rectangle.angled")
                }
            } footer: {
                Text("When on, every photo and video is backed up regardless of album.")
            }

            if !selection.backupAllPhotos {
                if selection.availableAlbums.isEmpty {
                    Section {
                        Text("No albums found")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let userAlbums = selection.availableAlbums.filter { !$0.isSmartAlbum }
                    let smartAlbums = selection.availableAlbums.filter { $0.isSmartAlbum }

                    if !userAlbums.isEmpty {
                        Section("My Albums") {
                            ForEach(userAlbums) { album in
                                AlbumToggleRow(album: album, selection: selection)
                            }
                        }
                    }

                    if !smartAlbums.isEmpty {
                        Section("Smart Albums") {
                            ForEach(smartAlbums) { album in
                                AlbumToggleRow(album: album, selection: selection)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Backup Sources")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { selection.loadAvailableAlbums() }
    }
}

private struct AlbumToggleRow: View {
    let album: SelectableAlbum
    let selection: BackupSelectionService

    var isOn: Bool { selection.selectedAlbumIds.contains(album.id) }

    var body: some View {
        HStack {
            Image(systemName: album.systemImage)
                .foregroundStyle(.blue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(album.title)
                Text("\(album.assetCount) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { isOn },
                set: { _ in selection.toggle(albumId: album.id) }
            ))
            .labelsHidden()
        }
    }
}
