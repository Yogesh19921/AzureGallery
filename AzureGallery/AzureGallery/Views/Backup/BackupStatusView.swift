import SwiftUI

struct BackupStatusView: View {
    @Environment(PhotoLibraryService.self) private var photoLibrary
    @State private var stats: BackupStats = .empty
    private let engine = BackupEngine.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BackupWidgetView(stats: stats)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section("Library") {
                    StatRow(label: "Total Photos",  value: stats.totalInLibrary)
                    StatRow(label: "Backed Up",     value: stats.uploaded,    color: .green)
                    StatRow(label: "Pending",       value: stats.pendingTotal, color: .orange)
                    StatRow(label: "Failed",        value: stats.allFailed,
                            color: stats.allFailed > 0 ? .red : .secondary)
                }

                Section("Status") {
                    HStack {
                        Label(
                            engine.isPaused ? "Paused" : (engine.activeUploads > 0 ? "Uploading" : "Idle"),
                            systemImage: engine.isPaused ? "pause.circle.fill" : (engine.activeUploads > 0 ? "arrow.up.circle.fill" : "checkmark.circle.fill")
                        )
                        .foregroundStyle(engine.isPaused ? .orange : (engine.activeUploads > 0 ? .blue : .green))
                        Spacer()
                        Button {
                            if engine.isPaused { engine.resume() } else { engine.pause() }
                        } label: {
                            Text(engine.isPaused ? "Resume" : "Pause")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(engine.isPaused ? .blue : .orange)
                        }
                        .buttonStyle(.plain)
                    }

                    NavigationLink {
                        ActiveUploadsView()
                    } label: {
                        HStack {
                            Text("Active Uploads")
                            Spacer()
                            if engine.activeUploads > 0 {
                                HStack(spacing: 6) {
                                    ProgressView().controlSize(.mini)
                                    Text("\(engine.activeUploads)")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Text("Idle").foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let date = stats.lastUploadedAt {
                        HStack {
                            Text("Last Upload")
                            Spacer()
                            Text(date, style: .relative)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }

                    NavigationLink {
                        RestoreView()
                    } label: {
                        HStack {
                            Text("Restore from Cloud")
                            Spacer()
                            Text("\(stats.uploaded)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Backup Status")
            .task { refreshStats() }
            // Refresh counts whenever an upload finishes or starts.
            .onChange(of: engine.activeUploads) { _, _ in refreshStats() }
        }
    }

    private func refreshStats() {
        stats = (try? DatabaseService.shared.stats(
            totalInLibrary: photoLibrary.totalCount
        )) ?? .empty
    }
}

// MARK: - Active uploads detail

struct ActiveUploadsView: View {
    private let engine = BackupEngine.shared

    var body: some View {
        let items = engine.activeUploadItems.values
            .sorted { $0.fileName < $1.fileName }

        List {
            if items.isEmpty {
                ContentUnavailableView(
                    "No Active Uploads",
                    systemImage: "icloud.and.arrow.up",
                    description: Text("No uploads are currently in progress.")
                )
            } else {
                ForEach(items) { item in
                    UploadProgressRow(item: item)
                }
            }
        }
        .navigationTitle("Active Uploads")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct UploadProgressRow: View {
    let item: ActiveUploadItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.fileName)
                .font(.subheadline)
                .lineLimit(1)
                .truncationMode(.middle)

            if let iCloudProgress = item.iCloudProgress {
                // iCloud download in progress — show a secondary progress bar
                HStack(spacing: 6) {
                    Image(systemName: "icloud.and.arrow.down")
                        .font(.caption)
                        .foregroundStyle(.cyan)
                    Text("Downloading from iCloud...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: iCloudProgress)
                    .tint(.cyan)

                HStack {
                    Spacer()
                    Text(String(format: "%.0f%%", iCloudProgress * 100))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ProgressView(value: item.progress)
                    .tint(.blue)

                HStack {
                    Text(formatted(item.bytesSent))
                    Text("of")
                    Text(item.totalBytes > 0 ? formatted(item.totalBytes) : "—")
                    Spacer()
                    Text(String(format: "%.0f%%", item.progress * 100))
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatted(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Shared stat row

private struct StatRow: View {
    let label: String
    let value: Int
    var color: Color = .primary

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text("\(value)")
                .foregroundStyle(color)
                .fontWeight(.medium)
        }
    }
}
