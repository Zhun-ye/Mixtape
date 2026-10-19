import Alamofire
import Foundation

/// Factory for creating configured Alamofire sessions for YouTube Music API requests.
enum YTMusicSession {
    /// Creates a configured Alamofire Session for API requests.
    /// Must be called from MainActor to access services.
    /// - Parameters:
    ///   - webKitManager: WebKitManager for cookie access
    ///   - authService: AuthService for session expiration handling
    /// - Returns: Configured Alamofire Session
    @MainActor
    static func create(webKitManager: WebKitManager, authService: AuthService) -> Session {
        let interceptor = YTMusicRequestInterceptor(
            webKitManager: webKitManager,
            authService: authService
        )

        let configuration = URLSessionConfiguration.default
        configuration.httpAdditionalHeaders = [
            "User-Agent": WebKitManager.userAgent,
        ]

        // Note: URLCache doesn't cache POST requests, so we use APICache instead
        // for two-level (memory + disk) caching with TTL support

        return Session(
            configuration: configuration,
            interceptor: interceptor,
            eventMonitors: [YTMusicEventMonitor()]
        )
    }
}
