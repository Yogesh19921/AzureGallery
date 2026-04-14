import SwiftUI

/// Settings view for enabling/disabling and configuring multiple cloud storage providers.
struct CloudProvidersView: View {
    @State private var refresh = false

    var body: some View {
        List {
            Section {
                Text("Enable multiple providers to mirror backups across services.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(CloudProviderType.allCases) { type in
                ProviderRow(type: type, refresh: $refresh)
            }
        }
        .navigationTitle("Cloud Providers")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ProviderRow: View {
    let type: CloudProviderType
    @Binding var refresh: Bool
    @State private var enabled: Bool
    @State private var showSetup = false

    init(type: CloudProviderType, refresh: Binding<Bool>) {
        self.type = type
        self._refresh = refresh
        self._enabled = State(initialValue: type.isEnabled || (UserDefaults.standard.object(forKey: type.enabledKey) == nil && type.isConfigured))
    }

    var body: some View {
        Section {
            HStack {
                Image(systemName: type.icon)
                    .foregroundStyle(.blue)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(type.rawValue).font(.body)
                    Text(type.isConfigured ? "Configured" : "Not configured")
                        .font(.caption)
                        .foregroundStyle(type.isConfigured ? .green : .secondary)
                }
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
                    .onChange(of: enabled) {
                        var t = type
                        t.isEnabled = enabled
                        refresh.toggle()
                    }
            }

            Button(type.isConfigured ? "Reconfigure…" : "Set Up…") {
                showSetup = true
            }
        }
        .sheet(isPresented: $showSetup) {
            NavigationStack {
                setupView
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showSetup = false }
                        }
                    }
            }
        }
    }

    @ViewBuilder
    private var setupView: some View {
        switch type {
        case .azure:
            AzureSetupView()
        case .s3:
            S3SetupView()
        case .gcp:
            GCPSetupView()
        }
    }
}
