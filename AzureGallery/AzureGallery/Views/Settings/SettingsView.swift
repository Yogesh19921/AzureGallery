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
    @State private var tempCacheBytes: Int64 = 0
    @State private var showClearCacheConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                // ── Account ──
                Section("Account") {
                    NavigationLink {
                        CloudProvidersView()
                    } label: {
                        HStack {
                            Label("Cloud Providers", systemImage: "cloud")
                            Spacer()
                            Text(activeProviderCount > 0 ? "\(activeProviderCount) active" : "Not set up")
                                .foregroundStyle(activeProviderCount > 0 ? .green : .secondary)
                                .font(.caption)
                        }
                    }
                    NavigationLink {
                        StorageDashboardView()
                    } label: {
                        Label("Storage & Cost", systemImage: "chart.bar")
                    }
                    Picker("Storage Tier", selection: $storageTier) {
                        Text("Account Default").tag("")
                        Text("Hot").tag("Hot")
                        Text("Cool").tag("Cool")
                        Text("Cold").tag("Cold")
                        Text("Archive").tag("Archive")
                    }
                    if storageTier == "Archive" {
                        Label("Archive files cannot be immediately downloaded.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }

                // ── Backup ──
                Section("Backup") {
                    NavigationLink {
                        BackupSourcesView()
                    } label: {
                        Label("Backup Sources", systemImage: "photo.on.rectangle.angled")
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
                    Button("Retry Failed Uploads") { showRetryConfirm = true }
                        .foregroundStyle(.orange)
                }

                // ── Search ──
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
                    Text("Runs Vision AI on your photos to enable search by content. On-device only.")
                }

                // ── App ──
                Section("App") {
                    Picker("Theme", selection: $appearanceMode) {
                        ForEach(AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    Button {
                        showClearCacheConfirm = true
                    } label: {
                        HStack {
                            Label("Clear Cache", systemImage: "trash")
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: tempCacheBytes, countStyle: .file))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .disabled(tempCacheBytes == 0)
                    NavigationLink {
                        LogsView()
                    } label: {
                        Label("Diagnostics", systemImage: "doc.text")
                    }
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("About", systemImage: "info.circle")
                    }
                }
            }
            .navigationTitle("Settings")
            .task {
                activeProviderCount = CloudProviderType.allCases.filter { $0.isConfigured && $0.isEnabled }.count
                tempCacheBytes = BackupEngine.shared.currentTempCacheSize()
            }
            .onAppear {
                activeProviderCount = CloudProviderType.allCases.filter { $0.isConfigured && $0.isEnabled }.count
                tempCacheBytes = BackupEngine.shared.currentTempCacheSize()
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
            .confirmationDialog(
                "Clear \(ByteCountFormatter.string(fromByteCount: tempCacheBytes, countStyle: .file)) of cached upload files?",
                isPresented: $showClearCacheConfirm,
                titleVisibility: .visible
            ) {
                Button("Clear", role: .destructive) {
                    let result = BackupEngine.shared.cleanupOrphanedTempFiles()
                    tempCacheBytes = BackupEngine.shared.currentTempCacheSize()
                    AppLogger.shared.info("Manual cache clear — removed \(result.removed) files, freed \(ByteCountFormatter.string(fromByteCount: result.bytesFreed, countStyle: .file))", tag: "Settings")
                }
            } message: {
                Text("In-flight uploads are preserved.")
            }
        }
    }
}

// MARK: - About

private struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AzureGallery")
                            .font(.title2.weight(.bold))
                        Text("Your photos, your cloud")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Info") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                LabeledContent("iOS", value: UIDevice.current.systemVersion)
            }

            Section("Stats") {
                let stats = (try? DatabaseService.shared.stats(totalInLibrary: 0)) ?? .empty
                LabeledContent("Photos Backed Up", value: "\(stats.uploaded)")
                LabeledContent("Pending", value: "\(stats.pendingTotal)")
                LabeledContent("Failed", value: "\(stats.allFailed)")
            }

            Section {
                Link(destination: URL(string: "https://github.com/Yogesh19921/AzureGallery")!) {
                    Label("GitHub", systemImage: "link")
                }
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
