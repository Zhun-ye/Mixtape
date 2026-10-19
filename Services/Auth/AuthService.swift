import Combine
import Foundation
import Observation
import os

/// Manages authentication state.
@MainActor
@Observable
final class AuthService: AuthServiceProtocol {
    /// Authentication states.
    enum State: Equatable, Sendable {
        case initializing
        case loggedOut
        case loggingIn
        case loggedIn(sapisid: String)

        var isLoggedIn: Bool {
            if case .loggedIn = self { return true }
            return false
        }
        
        var isLoggedOut: Bool {
            if case .loggedOut = self { return true }
            return false
        }

        var isInitializing: Bool {
            self == .initializing
        }
    }

    /// Current authentication state.
    private(set) var state: State {
        didSet {
            stateSubject.send(state)
        }
    }

    /// Publisher for authentication state changes. Emits current value on subscription.
    private let stateSubject: CurrentValueSubject<State, Never>
    var statePublisher: AnyPublisher<State, Never> { stateSubject.eraseToAnyPublisher() }

    /// Flag indicating whether re-authentication is needed.
    var needsReauth: Bool = false

    private let webKitManager: WebKitManagerProtocol

    //private let logger = DiagnosticsLogger.auth
    private let logger = Logger(.disabled)

    init(webKitManager: WebKitManagerProtocol) {
        self.webKitManager = webKitManager
        self.state = .initializing
        self.stateSubject = CurrentValueSubject(.initializing)
    }

    /// Starts the login flow by presenting the login sheet.
    func startLogin() {
        self.logger.info("Starting login flow")
        self.state = .loggingIn
    }

    /// Checks if the user is logged in based on existing cookies.
    /// Reads directly from Keychain backup for instant startup, avoiding WebKit delays.
    func checkLoginStatus() async {
        self.logger.debug("Checking login status from Keychain")

        // Check Keychain directly - no WebKit delay needed
        // Keychain is our source of truth for auth cookies
        if let cookies = CookieBackupManager.restoreCookies() {
            // Look for SAPISID in either secure or non-secure form
            let sapisidCookie = cookies.first { cookie in
                cookie.name == "__Secure-3PAPISID" || cookie.name == "SAPISID"
            }

            if let cookie = sapisidCookie {
                // Check expiration if present
                if let expiresDate = cookie.expiresDate {
                    if expiresDate > Date() {
                        self.logger.info("Found valid SAPISID in backup, user is logged in")
                        self.state = .loggedIn(sapisid: cookie.value)
                        self.needsReauth = false
                        return
                    } else {
                        self.logger.warning("SAPISID cookie has expired")
                    }
                } else {
                    // Session cookie without expiration - treat as valid
                    self.logger.info("Found session SAPISID in backup, user is logged in")
                    self.state = .loggedIn(sapisid: cookie.value)
                    self.needsReauth = false
                    return
                }
            }
        }

        self.logger.info("No valid SAPISID found in backup, user is logged out")
        self.state = .loggedOut

        // Clear stale account info if no valid auth cookies exist
        AppDefaults.shared.accountInfo = nil
        self.logger.info("Cleared stale account info")
    }

    /// Called when a session expires (e.g., 401/403 from API).
    func sessionExpired() {
        self.logger.warning("Session expired, requiring re-authentication")
        self.state = .loggedOut
        self.needsReauth = true
    }

    /// Signs out the user by clearing all cookies and data.
    func signOut() async {
        self.logger.info("Signing out user")

        await self.webKitManager.clearAllData()
        AppDefaults.shared.accountInfo = nil

        self.state = .loggedOut
        self.needsReauth = false

        self.logger.info("User signed out successfully")
    }

    /// Called when login completes successfully (from LoginSheet observation).
    func completeLogin(sapisid: String) {
        self.logger.info("Login completed successfully")
        self.state = .loggedIn(sapisid: sapisid)
        self.needsReauth = false
    }
}
