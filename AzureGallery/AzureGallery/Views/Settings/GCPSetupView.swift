import SwiftUI

struct GCPSetupView: View {
    @State private var accessKey: String = ""
    @State private var secret: String = ""
    @State private var bucket: String = ""
    @State private var projectId: String = ""
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var validationSuccess = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HMAC Access Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("GOOGTS7C7FUP3AIR...", text: $accessKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("HMAC Secret")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("Base64-encoded secret", text: $secret)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bucket Name")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("my-photo-backup", text: $bucket)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Project ID (optional)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("my-gcp-project", text: $projectId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                } header: {
                    Text("Google Cloud Storage")
                } footer: {
                    Text("Create HMAC keys in Google Cloud Console: Cloud Storage > Settings > Interoperability.")
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
                    .disabled(accessKey.isEmpty || secret.isEmpty || bucket.isEmpty || isValidating)

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
                    .disabled(accessKey.isEmpty || secret.isEmpty || bucket.isEmpty)
                }
            }
            .navigationTitle("GCP Setup")
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
        accessKey = KeychainHelper.load(key: KeychainHelper.gcpAccessKeyKey) ?? ""
        secret = KeychainHelper.load(key: KeychainHelper.gcpSecretKey) ?? ""
        bucket = KeychainHelper.load(key: KeychainHelper.gcpBucketKey) ?? ""
        projectId = KeychainHelper.load(key: KeychainHelper.gcpProjectIdKey) ?? ""
    }

    private func save() {
        KeychainHelper.save(accessKey, key: KeychainHelper.gcpAccessKeyKey)
        KeychainHelper.save(secret, key: KeychainHelper.gcpSecretKey)
        KeychainHelper.save(bucket, key: KeychainHelper.gcpBucketKey)
        if !projectId.isEmpty {
            KeychainHelper.save(projectId, key: KeychainHelper.gcpProjectIdKey)
        } else {
            KeychainHelper.delete(key: KeychainHelper.gcpProjectIdKey)
        }
    }

    private func validate() async {
        isValidating = true
        validationMessage = nil
        defer { isValidating = false }

        guard let secretData = Data(base64Encoded: secret) else {
            validationSuccess = false
            validationMessage = "HMAC secret is not valid base64"
            return
        }

        do {
            let config = GCPConfig(
                accessKey: accessKey,
                secret: secretData,
                bucket: bucket,
                projectId: projectId
            )
            let service = GCPBlobService(config: config)
            try await service.validate()
            validationSuccess = true
            validationMessage = "Connected successfully"
        } catch {
            validationSuccess = false
            validationMessage = error.localizedDescription
        }
    }
}
