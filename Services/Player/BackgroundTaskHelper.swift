import Foundation
#if os(iOS)
import UIKit
#endif

/// Helper for executing async operations with iOS background task protection.
enum BackgroundTaskHelper {
    /// Executes an async operation with background task protection.
    /// Ensures network requests and critical operations complete even when app is backgrounded.
    /// On macOS, this is a no-op passthrough.
    ///
    /// - Parameter operation: The async operation to execute
    /// - Returns: The result of the operation
    /// - Note: iOS gives ~30 seconds to complete before terminating the task
    @MainActor
    static func withBackgroundTask<T>(_ operation: () async throws -> T) async rethrows -> T {
        #if os(iOS)
        let taskID = UIApplication.shared.beginBackgroundTask {
            // Task expired - will be ended in defer block
        }

        defer {
            if taskID != .invalid {
                UIApplication.shared.endBackgroundTask(taskID)
            }
        }

        return try await operation()
        #else
        return try await operation()
        #endif
    }
}
