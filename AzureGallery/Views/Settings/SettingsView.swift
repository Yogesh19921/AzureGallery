import SwiftUI

struct SettingsView: View {
    @State private var showAzureSetup = false
    @State private var autoBackupEnabled: Bool = UserDefaults.standard.bool(forKey: "autoBackupEnabled")
    @State private var wifiOnlyEnabled: Bool = {
        let stored = UserDefaults.standard.object(forKey: "wifiOnly")
        return stored == nil ? true : UserDefaults.standard.bool(forKey: "wifiOnly")
    }()
    @State private var showRetryConfirm = false
    private var isConfigured: Bool { KeychainHelper.load(key: KeychainHelper.connectionStringKey) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section("Azure Storage") {
                    HStack {
                        Label("Configuration", systemImage: "cloud")
                        Spacer()
                        Text(isConfigured ? "Connected" : "Not set up")
                            .foregroundStyle(isConfigured ? .green : .secondary)
                            .font(.caption)
                    }
                    Button("Configure Azure…") { showAzureSetup = true }
                }

                Section("Backup") {
                    Toggle("Auto Backup", isOn: $autoBackupEnabled)
                        .onChange(of: autoBackupEnabled) {
                            UserDefaults.standard.set(autoBackupEnabled, forKey: "autoBackupEnabled")
                        }
                    Toggle("Wi-Fi Only", isOn: $wifiOnlyEnabled)
                        .onChange(of: wifiOnlyEnabled) {
                            UserDefaults.standard.set(wifiOnlyEnabled, forKey: "wifiOnly")
                        }
                }

                Section {
                    Button("Retry Failed Uploads") { showRetryConfirm = true }
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAzureSetup) {
                AzureSetupView()
            }
            .confirmationDialog("Retry all failed uploads?", isPresented: $showRetryConfirm) {
                Button("Retry") {
                    try? DatabaseService.shared.resetFailedToPending()
                    Task { await BackupEngine.shared.processQueue() }
                }
            }
        }
    }
}
