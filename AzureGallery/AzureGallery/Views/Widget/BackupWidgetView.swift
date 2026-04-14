import SwiftUI

/// A self-contained SwiftUI view that renders backup statistics in a widget-like card.
///
/// Designed to be embedded in-app (e.g. at the top of `BackupStatusView`) and is
/// also ready to be promoted to a real WidgetKit timeline entry view when the widget
/// target is added.
struct BackupWidgetView: View {
    let stats: BackupStats

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundStyle(.blue)
                Text("AzureGallery")
                    .font(.caption.weight(.semibold))
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(stats.uploaded)")
                    .font(.system(.title, design: .rounded, weight: .bold))
                Text("backed up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if stats.pendingTotal > 0 {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("\(stats.pendingTotal) pending")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }

            if stats.allFailed > 0 {
                Text("\(stats.allFailed) failed")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
