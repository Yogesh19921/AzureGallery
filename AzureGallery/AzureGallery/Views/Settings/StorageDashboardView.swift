import SwiftUI

/// Azure storage usage dashboard with cost estimation.
struct StorageDashboardView: View {
    @State private var loading = true
    @State private var blobCount: Int = 0
    @State private var totalBytes: Int64 = 0
    @State private var error: String?
    @AppStorage("storageTier") private var storageTier = "Cold"

    var body: some View {
        List {
            if loading {
                Section {
                    HStack {
                        ProgressView()
                        Text("Querying Azure…").foregroundStyle(.secondary)
                    }
                }
            } else if let err = error {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Button("Retry") { Task { await load() } }
                }
            } else {
                Section("Container Usage") {
                    DashboardRow(label: "Total Blobs", value: "\(blobCount)")
                    DashboardRow(label: "Storage Used", value: formattedBytes(totalBytes))
                }

                Section {
                    DashboardRow(label: "Tier", value: effectiveTier)
                    DashboardRow(label: "Storage", value: storageCost(bytes: totalBytes, tier: effectiveTier))
                    DashboardRow(label: "Write Ops (\(blobCount))", value: writeCost(ops: blobCount, tier: effectiveTier))
                    DashboardRow(label: "Read Ops (est.)", value: readCost(ops: blobCount / 10, tier: effectiveTier))

                    HStack {
                        Text("Total Estimate")
                            .fontWeight(.semibold)
                        Spacer()
                        Text(totalCost(bytes: totalBytes, writeOps: blobCount, readOps: blobCount / 10, tier: effectiveTier))
                            .fontWeight(.semibold)
                            .foregroundStyle(.blue)
                    }
                } header: {
                    Text("Estimated Monthly Cost")
                } footer: {
                    Text("Estimates based on Azure Blob Storage public pricing (USD). Actual costs may vary by region and agreement.")
                        .font(.caption2)
                }
            }
        }
        .navigationTitle("Storage & Cost")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loading = true
        error = nil
        guard let provider = CloudStorageFactory.makeProvider() else {
            error = "Cloud storage not configured"
            loading = false
            return
        }
        do {
            let stats = try await provider.containerStats()
            blobCount = stats.blobCount
            totalBytes = stats.totalBytes
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private var effectiveTier: String {
        storageTier.isEmpty ? "Cold" : storageTier
    }

    // MARK: - Cost calculations (per-GB/month, per-10K ops)

    // Azure public pricing (USD) as of 2025 — LRS, East US
    private func pricePerGBMonth(_ tier: String) -> Double {
        switch tier {
        case "Cool":    return 0.01
        case "Cold":    return 0.0036
        case "Archive": return 0.002
        default:        return 0.018  // Hot
        }
    }

    private func writePricePer10K(_ tier: String) -> Double {
        switch tier {
        case "Cool":    return 0.10
        case "Cold":    return 0.18
        case "Archive": return 0.11
        default:        return 0.055  // Hot
        }
    }

    private func readPricePer10K(_ tier: String) -> Double {
        switch tier {
        case "Cool":    return 0.01
        case "Cold":    return 0.10
        case "Archive": return 5.00
        default:        return 0.0044 // Hot
        }
    }

    private func storageCost(bytes: Int64, tier: String) -> String {
        let gb = Double(bytes) / 1_073_741_824
        let cost = gb * pricePerGBMonth(tier)
        return formatUSD(cost)
    }

    private func writeCost(ops: Int, tier: String) -> String {
        let cost = Double(ops) / 10_000 * writePricePer10K(tier)
        return formatUSD(cost)
    }

    private func readCost(ops: Int, tier: String) -> String {
        let cost = Double(ops) / 10_000 * readPricePer10K(tier)
        return formatUSD(cost)
    }

    private func totalCost(bytes: Int64, writeOps: Int, readOps: Int, tier: String) -> String {
        let gb = Double(bytes) / 1_073_741_824
        let storage = gb * pricePerGBMonth(tier)
        let writes  = Double(writeOps) / 10_000 * writePricePer10K(tier)
        let reads   = Double(readOps) / 10_000 * readPricePer10K(tier)
        return formatUSD(storage + writes + reads) + " /mo"
    }

    private func formatUSD(_ amount: Double) -> String {
        if amount < 0.01 { return "< $0.01" }
        return String(format: "$%.2f", amount)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct DashboardRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}
