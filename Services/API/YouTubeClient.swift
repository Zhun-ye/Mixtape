import Foundation

/// YouTube client configuration for different API contexts.
/// Different clients have different capabilities (login support, signature timestamp, etc.).
struct YouTubeClient: Sendable {
    let clientName: String
    let clientVersion: String
    let clientId: String
    let userAgent: String
    let osName: String?
    let osVersion: String?
    let deviceMake: String?
    let deviceModel: String?
    let androidSdkVersion: String?
    let loginSupported: Bool
    let useSignatureTimestamp: Bool
    let isEmbedded: Bool

    init(
        clientName: String,
        clientVersion: String,
        clientId: String,
        userAgent: String,
        osName: String? = nil,
        osVersion: String? = nil,
        deviceMake: String? = nil,
        deviceModel: String? = nil,
        androidSdkVersion: String? = nil,
        loginSupported: Bool = false,
        useSignatureTimestamp: Bool = false,
        isEmbedded: Bool = false
    ) {
        self.clientName = clientName
        self.clientVersion = clientVersion
        self.clientId = clientId
        self.userAgent = userAgent
        self.osName = osName
        self.osVersion = osVersion
        self.deviceMake = deviceMake
        self.deviceModel = deviceModel
        self.androidSdkVersion = androidSdkVersion
        self.loginSupported = loginSupported
        self.useSignatureTimestamp = useSignatureTimestamp
        self.isEmbedded = isEmbedded
    }

    /// Builds the context object for API requests.
    func toContext(
        locale: YouTubeLocale = .default,
        visitorData: String? = nil,
        dataSyncId: String? = nil
    ) -> [String: Any] {
        var client: [String: Any] = [
            "clientName": clientName,
            "clientVersion": clientVersion,
            "gl": locale.gl,
            "hl": locale.hl,
        ]

        if let osName { client["osName"] = osName }
        if let osVersion { client["osVersion"] = osVersion }
        if let deviceMake { client["deviceMake"] = deviceMake }
        if let deviceModel { client["deviceModel"] = deviceModel }
        if let androidSdkVersion { client["androidSdkVersion"] = androidSdkVersion }
        if let visitorData { client["visitorData"] = visitorData }

        var user: [String: Any] = [
            "lockedSafetyMode": false,
        ]

        if loginSupported, let dataSyncId {
            user["onBehalfOfUser"] = dataSyncId
        }

        return [
            "client": client,
            "user": user,
        ]
    }
}

// MARK: - YouTubeLocale

/// Locale settings for YouTube API requests.
struct YouTubeLocale: Sendable {
    let gl: String  // Geographic location (country code)
    let hl: String  // Host language

    static var `default`: YouTubeLocale {
        YouTubeLocale(
            gl: Locale.current.region?.identifier ?? "US",
            hl: Locale.current.language.languageCode?.identifier ?? "en"
        )
    }
}

// MARK: - Predefined Clients

extension YouTubeClient {
    /// User agent for web clients.
    static let userAgentWeb = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    /// YouTube Music origin URL.
    static let originYouTubeMusic = "https://music.youtube.com"

    /// YouTube Music referer URL.
    static let refererYouTubeMusic = "\(originYouTubeMusic)/"

    /// iOS YouTube client (no auth required, but limited to medium quality).
    static let ios = YouTubeClient(
        clientName: "IOS",
        clientVersion: "20.10.4",
        clientId: "5",
        userAgent: "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)",
        osName: "iOS",
        osVersion: "18.3.2.22D82",
        deviceMake: "Apple",
        deviceModel: "iPhone16,2"
    )

    /// YouTube Music web client (requires auth for premium streams).
    static let webRemix = YouTubeClient(
        clientName: "WEB_REMIX",
        clientVersion: "1.20250310.01.00",
        clientId: "67",
        userAgent: userAgentWeb,
        loginSupported: true,
        useSignatureTimestamp: true
    )

    /// Android VR client - Reliable streams with good quality.
    static let androidVR = YouTubeClient(
        clientName: "ANDROID_VR",
        clientVersion: "1.43.32",
        clientId: "28",
        userAgent: "com.google.android.apps.youtube.vr.oculus/1.43.32 (Linux; U; Android 12; en_US; Quest 3; Build/SQ3A.220605.009.A1; Cronet/107.0.5284.2)",
        osName: "Android",
        osVersion: "12",
        deviceMake: "Oculus",
        deviceModel: "Quest 3",
        androidSdkVersion: "32"
    )

    /// TVHTML5 embedded player client.
    static let tvhtml5 = YouTubeClient(
        clientName: "TVHTML5_SIMPLY_EMBEDDED_PLAYER",
        clientVersion: "2.0",
        clientId: "85",
        userAgent: "Mozilla/5.0 (PlayStation 4 5.55) AppleWebKit/601.2 (KHTML, like Gecko)",
        isEmbedded: true
    )

    /// Android Music client.
    static let androidMusic = YouTubeClient(
        clientName: "ANDROID_MUSIC",
        clientVersion: "7.27.52",
        clientId: "21",
        userAgent: "com.google.android.apps.youtube.music/7.27.52 (Linux; U; Android 14; en_US; Pixel 8 Pro; Build/UD1A.230803.041; Cronet/114.0.5735.27)",
        osName: "Android",
        osVersion: "14",
        deviceMake: "Google",
        deviceModel: "Pixel 8 Pro",
        androidSdkVersion: "34",
        loginSupported: true
    )

    /// Web client.
    static let web = YouTubeClient(
        clientName: "WEB",
        clientVersion: "2.20241126.01.00",
        clientId: "1",
        userAgent: userAgentWeb
    )

    /// Fallback order for stream fetching - prioritize WEB_REMIX for Premium 256kbps AAC.
    static let streamFallbackClients: [YouTubeClient] = [
        .webRemix,       // Premium formats (256kbps AAC) - try first!
        .androidMusic,   // Android Music client (may have premium)
        .androidVR,      // Main fallback - reliable streams
        .tvhtml5,        // TV embedded player
        .ios,            // iOS fallback
        .web,            // Web client fallback
    ]
}
