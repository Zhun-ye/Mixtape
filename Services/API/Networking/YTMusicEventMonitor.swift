import Alamofire
import Foundation
import os

/// Event monitor for logging YouTube Music API requests and responses.
final class YTMusicEventMonitor: EventMonitor {
    private let logger = DiagnosticsLogger.api

    // MARK: - Request Events

    func request(_ request: Request, didCreateURLRequest urlRequest: URLRequest) {
        let method = urlRequest.httpMethod ?? "?"
        let url = urlRequest.url?.absoluteString ?? "unknown"
        self.logger.info("➡️ \(method) \(url)")
    }

    // MARK: - Response Events

    func request(_ request: DataRequest, didParseResponse response: DataResponse<Data?, AFError>) {
        let method = request.request?.httpMethod ?? "?"
        let url = request.request?.url?.absoluteString ?? "unknown"
        let statusCode = response.response?.statusCode ?? 0
        let duration = response.metrics.map { String(format: "%.2fs", $0.taskInterval.duration) } ?? "?"
        let cacheStatus = cacheStatus(from: response.metrics)

        switch response.result {
        case .success:
            let size = response.data.map { ByteCountFormatter.string(fromByteCount: Int64($0.count), countStyle: .file) } ?? "0"
            self.logger.info("\(cacheStatus.emoji) \(statusCode) \(method) \(url) [\(duration), \(size)\(cacheStatus.suffix)]")

        case let .failure(error):
            self.logger.error("❌ \(statusCode) \(method) \(url) [\(duration)] - \(error.localizedDescription)")
        }
    }

    // MARK: - Cache Detection

    private func cacheStatus(from metrics: URLSessionTaskMetrics?) -> (emoji: String, suffix: String) {
        guard let transactionMetrics = metrics?.transactionMetrics.last else {
            return ("✅", "")
        }

        switch transactionMetrics.resourceFetchType {
        case .localCache:
            return ("💾", ", cache")
        case .serverPush:
            return ("⚡️", ", push")
        case .networkLoad:
            return ("✅", "")
        case .unknown:
            return ("✅", "")
        @unknown default:
            return ("✅", "")
        }
    }

    // MARK: - Retry Events

    func requestIsRetrying(_ request: Request) {
        let url = request.request?.url?.absoluteString ?? "unknown"
        self.logger.warning("🔄 Retrying request (attempt \(request.retryCount + 1)): \(url)")
    }
}
