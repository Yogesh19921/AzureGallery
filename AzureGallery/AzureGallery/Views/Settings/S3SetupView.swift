import SwiftUI

struct S3SetupView: View {
    @State private var selectedPreset = "aws"
    @State private var accessKeyId = ""
    @State private var secretAccessKey = ""
    @State private var bucket = ""
    @State private var region = "us-east-1"
    @State private var customEndpoint = ""
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var validationSuccess = false
    @Environment(\.dismiss) private var dismiss

    private var preset: S3Config.ProviderPreset {
        S3Config.presets.first { $0.id == selectedPreset } ?? S3Config.presets[0]
    }

    var body: some View {
        NavigationStack {
            Form {
                // Provider picker
                Section {
                    Picker("Provider", selection: $selectedPreset) {
                        ForEach(S3Config.presets) { p in
                            Text(p.name).tag(p.id)
                        }
                    }
                    .onChange(of: selectedPreset) {
                        // Reset region to first available for the new preset
                        region = preset.regions.first?.id ?? "us-east-1"
                        updateEndpoint()
                    }
                }

                // Credentials
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Access Key ID").font(.caption).foregroundStyle(.secondary)
                        TextField("AKIAIOSFODNN7EXAMPLE", text: $accessKeyId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Secret Access Key").font(.caption).foregroundStyle(.secondary)
                        SecureField("Your secret access key", text: $secretAccessKey)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Bucket Name").font(.caption).foregroundStyle(.secondary)
                        TextField("my-photo-backup", text: $bucket)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }

                    Picker("Region", selection: $region) {
                        ForEach(preset.regions, id: \.id) { r in
                            Text("\(r.name) (\(r.id))").tag(r.id)
                        }
                    }
                    .onChange(of: region) { updateEndpoint() }
                } header: {
                    Text("Credentials")
                } footer: {
                    Text(preset.helpText)
                }

                // Endpoint
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("S3 Endpoint").font(.caption).foregroundStyle(.secondary)
                        TextField("s3.us-west-004.backblazeb2.com", text: $customEndpoint)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.caption, design: .monospaced))
                    }
                } header: {
                    Text("Endpoint")
                } footer: {
                    Text(selectedPreset == "aws" ? "Leave empty for standard AWS S3." : "Auto-filled from provider. Edit if needed.")
                }

                // Test + Save
                Section {
                    Button {
                        Task { await validate() }
                    } label: {
                        HStack {
                            Text("Test Connection")
                            Spacer()
                            if isValidating { ProgressView() }
                        }
                    }
                    .disabled(accessKeyId.isEmpty || secretAccessKey.isEmpty || bucket.isEmpty || isValidating)

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
                    .disabled(accessKeyId.isEmpty || secretAccessKey.isEmpty || bucket.isEmpty)
                }
            }
            .navigationTitle("S3 Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear(perform: loadExisting)
    }

    private func updateEndpoint() {
        guard selectedPreset != "aws" else {
            customEndpoint = ""
            return
        }
        let template = preset.endpointTemplate
        guard template != "custom" else { return }  // MinIO — user fills in manually
        customEndpoint = template
            .replacingOccurrences(of: "{region}", with: region)
            .replacingOccurrences(of: "{account_id}", with: accessKeyId)
    }

    private func loadExisting() {
        accessKeyId = KeychainHelper.load(key: KeychainHelper.s3AccessKeyIdKey) ?? ""
        secretAccessKey = KeychainHelper.load(key: KeychainHelper.s3SecretAccessKeyKey) ?? ""
        bucket = KeychainHelper.load(key: KeychainHelper.s3BucketKey) ?? ""
        region = KeychainHelper.load(key: KeychainHelper.s3RegionKey) ?? "us-east-1"
        customEndpoint = KeychainHelper.load(key: KeychainHelper.s3EndpointKey) ?? ""
    }

    private func save() {
        KeychainHelper.save(accessKeyId, key: KeychainHelper.s3AccessKeyIdKey)
        KeychainHelper.save(secretAccessKey, key: KeychainHelper.s3SecretAccessKeyKey)
        KeychainHelper.save(bucket, key: KeychainHelper.s3BucketKey)
        KeychainHelper.save(region, key: KeychainHelper.s3RegionKey)
        if !customEndpoint.isEmpty {
            KeychainHelper.save(customEndpoint, key: KeychainHelper.s3EndpointKey)
        } else {
            KeychainHelper.delete(key: KeychainHelper.s3EndpointKey)
        }
    }

    private func validate() async {
        isValidating = true
        validationMessage = nil
        defer { isValidating = false }

        do {
            let config = S3Config(
                accessKeyId: accessKeyId,
                secretAccessKey: secretAccessKey,
                bucket: bucket,
                region: region,
                customEndpoint: customEndpoint.isEmpty ? nil : customEndpoint
            )
            try await S3BlobService(config: config).validate()
            validationSuccess = true
            validationMessage = "Connected successfully"
        } catch {
            validationSuccess = false
            validationMessage = error.localizedDescription
        }
    }
}
