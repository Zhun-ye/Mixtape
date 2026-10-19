import SwiftUI
import Kingfisher

/// A view that displays the user's profile image and optionally their name.
struct UserProfileView: View {
    /// The size of the profile image.
    let imageSize: CGFloat

    /// Whether to show the account name (macOS sidebar style).
    let showName: Bool

    /// Account info from UserDefaults (auto-updates via @AppStorage).
    @AppStorage(AppDefaults.Keys.accountInfo) private var accountInfo: AccountInfo?

    init(imageSize: CGFloat = 28, showName: Bool = false) {
        self.imageSize = imageSize
        self.showName = showName
    }

    var body: some View {
        Group {
            if showName {
                HStack {
                    profileImage()
                    Text(accountInfo?.name ?? "Settings").fontWeight(.medium)
                    Spacer()
                }
                .contentShape(Rectangle())
            } else {
                profileImage()
            }
        }
    }

    // MARK: - Private Views

    @ViewBuilder
    private func profileImage() -> some View {
        if let thumbnailURL = accountInfo?.thumbnailURLValue {
            KFImage(thumbnailURL)
                .interpolation(.high)
                .placeholder { fallbackImage }
                .cancelOnDisappear(true)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: imageSize, height: imageSize)
                .clipShape(Circle())
        } else {
            fallbackImage
        }
    }

    private var fallbackImage: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .padding(2)
            .frame(width: imageSize, height: imageSize)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.75, green: 0.78, blue: 0.85),
                        Color(red: 0.58, green: 0.62, blue: 0.72)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}
