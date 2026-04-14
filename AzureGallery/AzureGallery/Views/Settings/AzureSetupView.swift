import SwiftUI

struct AzureSetupView: View {
    @State private var connectionString: String = ""
    @State private var containerName: String = "photos"
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var validationSuccess = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connection String")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("DefaultEndpointsProtocol=https;AccountName=...", text: $connectionString, axis: .vertical)
                            .lineLimit(3...6)
                            .font(.caption)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    TextField("Container Name", text: $containerName)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Azure Storage")
                } footer: {
                    Text("Find your connection string in Azure Portal → Storage Account → Access Keys.")
                }

                Section {
                    Button {
                        Task { await validate() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isValidating {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(connectionString.isEmpty || isValidating)

                    if let msg = validationMessage {
                        Label(msg, systemImage: validationSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(validationSuccess ? .green : .red)
                            .font(.caption)
                    }
                }

                Section {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(connectionString.isEmpty)
                }
            }
            .navigationTitle("Azure Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadExisting)
    }

    private func loadExisting() {
        connectionString = KeychainHelper.load(key: KeychainHelper.connectionStringKey) ?? ""
        containerName = KeychainHelper.load(key: KeychainHelper.containerNameKey) ?? "photos"
    }

    private func save() {
        KeychainHelper.save(connectionString, key: KeychainHelper.connectionStringKey)
        KeychainHelper.save(containerName, key: KeychainHelper.containerNameKey)
    }

    private func validate() async {
        isValidating = true
        validationMessage = nil
        defer { isValidating = false }

        do {
            let config = try AzureConfig.parse(connectionString: connectionString, containerName: containerName)
            let service = AzureBlobService(config: config)
            try await service.validateConnection()
            validationSuccess = true
            validationMessage = "Connected successfully"
        } catch {
            validationSuccess = false
            validationMessage = error.localizedDescription
        }
    }
}
