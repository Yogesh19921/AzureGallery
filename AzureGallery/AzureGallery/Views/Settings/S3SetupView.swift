import SwiftUI

struct S3SetupView: View {
    @State private var accessKeyId: String = ""
    @State private var secretAccessKey: String = ""
    @State private var bucket: String = ""
    @State private var region: String = "us-east-1"
    @State private var isValidating = false
    @State private var validationMessage: String?
    @State private var validationSuccess = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Access Key ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("AKIAIOSFODNN7EXAMPLE", text: $accessKeyId)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .font(.system(.body, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Secret Access Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SecureField("Your secret access key", text: $secretAccessKey)
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

                    Picker("Region", selection: $region) {
                        ForEach(S3Config.commonRegions, id: \.id) { r in
                            Text("\(r.name) (\(r.id))").tag(r.id)
                        }
                    }
                } header: {
                    Text("Amazon S3")
                } footer: {
                    Text("Create an IAM user with S3 access in the AWS Console. Use the access key and secret from that user.")
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

    private func loadExisting() {
        accessKeyId = KeychainHelper.load(key: KeychainHelper.s3AccessKeyIdKey) ?? ""
        secretAccessKey = KeychainHelper.load(key: KeychainHelper.s3SecretAccessKeyKey) ?? ""
        bucket = KeychainHelper.load(key: KeychainHelper.s3BucketKey) ?? ""
        region = KeychainHelper.load(key: KeychainHelper.s3RegionKey) ?? "us-east-1"
    }

    private func save() {
        KeychainHelper.save(accessKeyId, key: KeychainHelper.s3AccessKeyIdKey)
        KeychainHelper.save(secretAccessKey, key: KeychainHelper.s3SecretAccessKeyKey)
        KeychainHelper.save(bucket, key: KeychainHelper.s3BucketKey)
        KeychainHelper.save(region, key: KeychainHelper.s3RegionKey)
        UserDefaults.standard.set(CloudProviderType.s3.rawValue, forKey: "cloudProviderType")
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
                region: region
            )
            let service = S3BlobService(config: config)
            try await service.validate()
            validationSuccess = true
            validationMessage = "Connected successfully"
        } catch {
            validationSuccess = false
            validationMessage = error.localizedDescription
        }
    }
}
