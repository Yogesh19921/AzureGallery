import SwiftUI
import Photos

/// Three-screen onboarding walkthrough shown on first launch.
///
/// 1. Welcome  -- app icon & tagline
/// 2. Photo Access -- explains permission, button to request
/// 3. Azure Setup -- explains cloud connection, offers configuration
///
/// Sets `UserDefaults "hasCompletedOnboarding"` to `true` on completion so
/// the flow is never shown again.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0
    @State private var showAzureSetup = false
    @State private var photoAccessGranted = false

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                welcomePage.tag(0)
                photoAccessPage.tag(1)
                azureSetupPage.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .sheet(isPresented: $showAzureSetup) {
            AzureSetupView()
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cloud.fill")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("AzureGallery")
                .font(.title.bold())

            Text("Your photos, safely backed up to Azure Cloud")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Spacer()

            Button {
                withAnimation { currentPage = 1 }
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Page 2: Photo Access

    private var photoAccessPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Photo Access")
                .font(.title.bold())

            Text("AzureGallery needs access to your photo library to discover and back up your photos. Your photos stay on-device -- only copies are uploaded to your Azure storage.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            if photoAccessGranted {
                Label("Access Granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            } else {
                Button {
                    Task {
                        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                        await MainActor.run {
                            photoAccessGranted = (status == .authorized || status == .limited)
                        }
                    }
                } label: {
                    Text("Allow Access")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 40)
            }

            Spacer()

            Button {
                withAnimation { currentPage = 2 }
            } label: {
                Text("Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
        .onAppear {
            let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
            photoAccessGranted = (status == .authorized || status == .limited)
        }
    }

    // MARK: - Page 3: Azure Setup

    private var azureSetupPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "server.rack")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("Azure Setup")
                .font(.title.bold())

            Text("Connect your Azure Blob Storage account to start backing up. You can also configure this later in Settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button {
                showAzureSetup = true
            } label: {
                Text("Configure Azure")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Button {
                completeOnboarding()
            } label: {
                Text("Skip for Now")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 40)

            Spacer()

            Button {
                completeOnboarding()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            .padding(.bottom, 60)
        }
    }

    // MARK: - Helpers

    private func completeOnboarding() {
        hasCompletedOnboarding = true
    }
}
