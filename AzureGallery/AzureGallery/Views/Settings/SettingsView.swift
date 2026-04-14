import SwiftUI

struct SettingsView: View {
    @State private var showAzureSetup = false
    @State private var autoBackupEnabled: Bool = UserDefaults.standard.bool(forKey: "autoBackupEnabled")
    @State private var wifiOnlyEnabled: Bool = {
        let stored = UserDefaults.standard.object(forKey: "wifiOnly")
        return stored == nil ? true : UserDefaults.standard.bool(forKey: "wifiOnly")
    }()
    @State private var showRetryConfirm = false
    @State private var chargeOnlyEnabled: Bool = UserDefaults.standard.bool(forKey: "chargeOnly")
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system
    @AppStorage("storageTier") private var storageTier = ""
    @AppStorage("maxConcurrentUploads") private var maxConcurrentUploads = 10

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
                    if isConfigured {
                        NavigationLink("Storage & Cost") {
                            StorageDashboardView()
                        }
                    }
                }

                Section("Backup") {
                    NavigationLink("Backup Sources") {
                        BackupSourcesView()
                    }

                    Toggle("Auto Backup", isOn: $autoBackupEnabled)
                        .onChange(of: autoBackupEnabled) {
                            UserDefaults.standard.set(autoBackupEnabled, forKey: "autoBackupEnabled")
                        }
                    Toggle("Wi-Fi Only", isOn: $wifiOnlyEnabled)
                        .onChange(of: wifiOnlyEnabled) {
                            UserDefaults.standard.set(wifiOnlyEnabled, forKey: "wifiOnly")
                        }
                    Toggle("Charge Only", isOn: $chargeOnlyEnabled)
                        .onChange(of: chargeOnlyEnabled) {
                            UserDefaults.standard.set(chargeOnlyEnabled, forKey: "chargeOnly")
                        }
                    Stepper("Concurrent Uploads: \(maxConcurrentUploads)", value: $maxConcurrentUploads, in: 1...20)
                }

                Section("Storage") {
                    Picker("Access Tier", selection: $storageTier) {
                        Text("Account Default").tag("")
                        Text("Hot").tag("Hot")
                        Text("Cool").tag("Cool")
                        Text("Cold").tag("Cold")
                        Text("Archive").tag("Archive")
                    }
                    if storageTier == "Archive" {
                        Label("Archive files cannot be immediately downloaded. Rehydration may take hours.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Diagnostics") {
                    NavigationLink("Logs") {
                        LogsView()
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
