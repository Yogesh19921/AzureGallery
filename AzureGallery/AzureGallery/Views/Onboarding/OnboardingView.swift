import SwiftUI
import Photos

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var showAzureSetup = false
    @State private var photoAccessGranted = false

    var body: some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color(.systemBackground), .blue.opacity(0.08)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $currentPage) {
                    welcomePage.tag(0)
                    photoAccessPage.tag(1)
                    cloudSetupPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .sheet(isPresented: $showAzureSetup) {
            NavigationStack {
                AzureSetupView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { showAzureSetup = false }
                        }
                    }
            }
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cloud.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, options: .repeating)

            Text("AzureGallery")
                .font(.largeTitle.bold())

            Text("Your photos, backed up to\nyour own cloud storage")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Text("10x cheaper than iCloud. You own the data.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)

            Spacer()
            Spacer()

            nextButton(page: 1)
        }
    }

    // MARK: - Page 2: Photo Access

    private var photoAccessPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 72))
                .foregroundStyle(.green)

            Text("Photo Access")
                .font(.largeTitle.bold())

            Text("AzureGallery needs access to your photo library to discover and back up your photos.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("Your photos stay on-device.\nOnly copies are uploaded to your storage.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            if photoAccessGranted {
                Label("Access Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                    .padding(.top, 8)
            } else {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        await MainActor.run {
                            photoAccessGranted = (status == .authorized || status == .limited)
                        }
                    }
                } label: {
                    Label("Allow Photo Access", systemImage: "photo.badge.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.large)
                .padding(.horizontal, 40)
                .padding(.top, 8)
            }

            Spacer()
            Spacer()

            nextButton(page: 2)
        }
        .onAppear {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            photoAccessGranted = (status == .authorized || status == .limited)
        }
    }

    // MARK: - Page 3: Cloud Setup

    private var cloudSetupPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cloud.bolt.fill")
                .font(.system(size: 72))
                .foregroundStyle(.orange)

            Text("Connect Your Cloud")
                .font(.largeTitle.bold())

            Text("Set up Azure, Amazon S3, or Google Cloud.\nOr skip and configure later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                showAzureSetup = true
            } label: {
                Label("Configure Now", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Spacer()
            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                completeOnboarding()
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Helpers

    private func nextButton(page: Int) -> some View {
        Button {
            withAnimation { currentPage = page }
        } label: {
            Text("Continue")
                .font(.headline)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(.horizontal, 40)
        .padding(.bottom, 60)
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}
