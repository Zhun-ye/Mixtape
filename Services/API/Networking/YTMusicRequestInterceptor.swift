@preconcurrency import Alamofire
import CryptoKit
import Foundation
import os

/// Alamofire interceptor for YouTube Music API authentication and retry.
/// Implements RequestAdapter for SAPISIDHASH auth header injection and
/// RequestRetrier for exponential backoff retry logic.
final class YTMusicRequestInterceptor: RequestInterceptor {
    private let webKitManager: WebKitManager
    private let authService: AuthService

    //private let logger = DiagnosticsLogger.api
    let logger = Logger(.disabled)

    // Retry configuration (matches existing RetryPolicy)
    private let maxRetryCount = 3
    private let baseDelay: TimeInterval = 1.0
    private let maxDelay: TimeInterval = 8.0

    init(webKitManager: WebKitManager, authService: AuthService) {
        self.webKitManager = webKitManager
        self.authService = authService
    }

    // MARK: - RequestAdapter (async version)

    func adapt(_ urlRequest: URLRequest, for _: Session) async throws -> URLRequest {
        var request = urlRequest
        let headers = try await self.buildAuthHeaders()
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        return request
    }

    // MARK: - RequestRetrier

    func retry(_ request: Request, for _: Session, dueTo error: any Error, completion: @escaping (RetryResult) -> Void) {
        let retryCount = request.retryCount

        // Map error to YTMusicError for consistent handling
        let ytError = self.mapToYTMusicError(error, response: request.response)

        // Auth errors: trigger session expired and do NOT retry
        if case .authExpired = ytError {
            Task { @MainActor in
                self.authService.sessionExpired()
            }
            completion(.doNotRetry)
            return
        }

        if case .notAuthenticated = ytError {
            completion(.doNotRetry)
            return
        }

        // Check retryability and count
        guard ytError.isRetryable, retryCount < self.maxRetryCount else {
            completion(.doNotRetry)
            return
        }

        // Exponential backoff: 1s, 2s, 4s (max 8s)
        let delay = min(self.baseDelay * pow(2.0, Double(retryCount)), self.maxDelay)
        self.logger.info("Retrying request (attempt \(retryCount + 1)) after \(delay)s")
        completion(.retryWithDelay(delay))
    }

    // MARK: - Private Helpers

    /// Builds authentication headers for API requests.
    @MainActor
    private func buildAuthHeaders() async throws -> [String: String] {
        // Log available cookies for debugging auth issues
        let allCookies = await self.webKitManager.getAllCookies()
        let youtubeCookies = await self.webKitManager.getCookies(for: "youtube.com")
        self.logger.debug("Building auth headers - total cookies: \(allCookies.count), youtube.com cookies: \(youtubeCookies.count)")

        guard let cookieHeader = await webKitManager.cookieHeader(for: "youtube.com") else {
            self.logger.error("No cookies found for youtube.com domain")
            throw YTMusicError.notAuthenticated
        }

        guard let sapisid = await webKitManager.getSAPISID() else {
            self.logger.error("SAPISID cookie not found or expired")
            throw YTMusicError.authExpired
        }

        // Compute SAPISIDHASH
        let origin = WebKitManager.origin
        let timestamp = Int(Date().timeIntervalSince1970)
        let hashInput = "\(timestamp) \(sapisid) \(origin)"
        let hash = Insecure.SHA1.hash(data: Data(hashInput.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        let sapisidhash = "\(timestamp)_\(hash)"

        return [
            "Cookie": cookieHeader,
            "Authorization": "SAPISIDHASH \(sapisidhash)",
            "Origin": origin,
            "Referer": origin,
            "Content-Type": "application/json",
            "Accept-Encoding": "gzip, deflate, br",
            "X-Goog-AuthUser": "0",
            "X-Origin": origin,
        ]
    }

    /// Maps Alamofire errors and HTTP responses to YTMusicError.
    private func mapToYTMusicError(_ error: any Error, response: HTTPURLResponse?) -> YTMusicError {
        // Check for auth errors from status code first
        if let statusCode = response?.statusCode {
            if statusCode == 401 || statusCode == 403 {
                return .authExpired
            }
            if !(200 ..< 300).contains(statusCode) {
                return .apiError(message: "HTTP \(statusCode)", code: statusCode)
            }
        }

        // Handle AFError types
        if let afError = error as? AFError {
            switch afError {
            case let .sessionTaskFailed(underlying):
                return .networkError(underlying: underlying)
            case let .responseValidationFailed(reason):
                if case let .unacceptableStatusCode(code) = reason {
                    if code == 401 || code == 403 {
                        return .authExpired
                    }
                    return .apiError(message: "HTTP \(code)", code: code)
                }
                return .unknown(message: afError.localizedDescription)
            case .responseSerializationFailed:
                return .parseError(message: afError.localizedDescription)
            default:
                return .networkError(underlying: afError)
            }
        }

        // Handle YTMusicError passthrough
        if let ytError = error as? YTMusicError {
            return ytError
        }

        // Default to network error
        return .networkError(underlying: error)
    }
}
