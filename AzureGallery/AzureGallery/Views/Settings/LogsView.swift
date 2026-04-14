import SwiftUI

struct LogsView: View {
    @State private var logger = AppLogger.shared
    @State private var filterLevel: LogEntry.Level? = nil
    @State private var shareText: String? = nil
    @State private var showClearConfirm = false

    private var displayed: [LogEntry] {
        guard let level = filterLevel else { return logger.entries.reversed() }
        return logger.entries.filter { $0.level == level }.reversed()
    }

    var body: some View {
        List {
            if displayed.isEmpty {
                ContentUnavailableView(
                    "No Logs",
                    systemImage: "doc.text",
                    description: Text("Logs appear here once backup activity starts.")
                )
            } else {
                ForEach(displayed) { entry in
                    LogRow(entry: entry)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button("All Levels") { filterLevel = nil }
                    Button("Errors Only") { filterLevel = .error }
                    Button("Warnings Only") { filterLevel = .warn }
                    Button("Info Only") { filterLevel = .info }
                } label: {
                    Image(systemName: filterLevel == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }

                ShareLink(item: logger.exportText()) {
                    Image(systemName: "square.and.arrow.up")
                }

                Button(role: .destructive) {
                    showClearConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .confirmationDialog("Clear all logs?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear Logs", role: .destructive) { logger.clear() }
        }
    }
}

// MARK: - Log Row

private struct LogRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(entry.level.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(levelColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(levelColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))

                Text(entry.tag)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(entry.shortTime)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    private var levelColor: Color {
        switch entry.level {
        case .error: return .red
        case .warn:  return .orange
        case .info:  return .secondary
        }
    }
}
