import SwiftUI

struct BackupStatusView: View {
    let stats: BackupStats
    private let engine = BackupEngine.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    StatRow(label: "Total Photos", value: stats.totalInLibrary)
                    StatRow(label: "Backed Up", value: stats.uploaded, color: .green)
                    StatRow(label: "Pending", value: stats.pendingTotal, color: .orange)
                    StatRow(label: "Failed", value: stats.allFailed, color: stats.allFailed > 0 ? .red : .secondary)
                }

                Section("Status") {
                    HStack {
                        Text("Active Uploads")
                        Spacer()
                        if engine.activeUploads > 0 {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("\(engine.activeUploads)")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            Text("Idle")
                                .foregroundStyle(.secondary)
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
                }
            }
            .navigationTitle("Backup Status")
        }
    }
}

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
