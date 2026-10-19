import SwiftUI

// MARK: - OnboardingView

/// Onboarding view shown to users before they sign in.
struct SignInView: View {
    @State private var showLoginSheet = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Hero
            VStack(spacing: 24) {
                Image(.appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80)

                VStack(spacing: 8) {
                    Text("Youtube Music")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                }
            }

            // Features
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    FeatureChipInternal(icon: "play.fill", text: "Background playback")
                    FeatureChipInternal(icon: "keyboard", text: "Media keys")
                }
                HStack(spacing: 12) {
                    FeatureChipInternal(icon: "bell.fill", text: "Notifications")
                    FeatureChipInternal(icon: "heart.fill", text: "Your library")
                }
            }

            Spacer()

            // Sign in
            VStack(spacing: 16) {
                Button {
                    showLoginSheet = true
                } label: {
                    Text("Sign in with Google")
                        .font(.headline)
                        .frame(maxWidth: 260)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Connect your YouTube Music account")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
                .frame(height: 24)

            // Disclaimer
            Text("Mixtape has no affiliation with Google or YouTube.\nYouTube Music is a trademark of Google Inc.")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 16)
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 520)
        #endif
        .sheet(isPresented: $showLoginSheet) {
            LoginSheet()
        }
    }
}

// MARK: - FeatureChip

private struct FeatureChipInternal: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
            Text(text)
                .font(.subheadline)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.fill.tertiary, in: Capsule())
    }
}

#Preview {
    SignInView()
}
