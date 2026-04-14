import SwiftUI
import Combine

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
    @AppStorage("storageTier") private var storageTier = "Cold"
    @AppStorage("maxConcurrentUploads") private var maxConcurrentUploads = 10

    @State private var activeProviderCount = 0
    @State private var isAnalyzing = false
    @State private var analysisText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Cloud Storage") {
                    NavigationLink {
                        CloudProvidersView()
                    } label: {
                        HStack {
                            Label("Providers", systemImage: "cloud")
                            Spacer()
                            Text(activeProviderCount > 0 ? "\(activeProviderCount) active" : "Not set up")
                                .foregroundStyle(activeProviderCount > 0 ? .green : .secondary)
                                .font(.caption)
                        }
                    }
                    NavigationLink("Storage & Cost") {
                        StorageDashboardView()
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

                Section {
                    if isAnalyzing {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text(analysisText)
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        Button("Re-analyze Library for Search") {
                            isAnalyzing = true
                            Task {
                                await BackupEngine.shared.reanalyzeExisting()
                                isAnalyzing = false
                            }
                        }
                    }
                } header: {
                    Text("Search")
                } footer: {
                    Text("Runs Vision AI on your photos to enable search by content (animals, text, scenes). Runs on-device.")
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
            .task {
                activeProviderCount = CloudProviderType.allCases.filter { $0.isConfigured && $0.isEnabled }.count
            }
            .onAppear {
                activeProviderCount = CloudProviderType.allCases.filter { $0.isConfigured && $0.isEnabled }.count
            }
            .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
                let ap = BackupEngine.analysisProgress
                if ap.isRunning {
                    isAnalyzing = true
                    analysisText = "Analyzing \(ap.completed)/\(ap.total)…"
                } else if isAnalyzing {
                    isAnalyzing = false
                }
            }
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
