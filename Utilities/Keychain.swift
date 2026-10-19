//
//  Keychain.swift
//  Mixtape
//
//  Minimal generic-password Keychain wrapper keyed by the app's bundle identifier.
//

import Foundation
import Security

// MARK: - KeychainError

enum KeychainError: Error {
    case unhandled(OSStatus)
}

// MARK: - Keychain

struct Keychain {
    let service: String

    init(service: String = Bundle.main.bundleIdentifier ?? "Mixtape") {
        self.service = service
    }

    /// Stores `data` for `key`, replacing any existing value.
    func set(_ data: Data, key: String) throws {
        let status = SecItemUpdate(
            self.query(for: key) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var attributes = self.query(for: key)
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(attributes as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError.unhandled(status)
        }
    }

    /// Returns the data stored for `key`, or `nil` if none exists.
    func getData(_ key: String) throws -> Data? {
        var query = self.query(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandled(status)
        }
    }

    /// Removes the value stored for `key`. Succeeds if nothing was stored.
    func remove(_ key: String) throws {
        let status = SecItemDelete(self.query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    private func query(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: self.service,
            kSecAttrAccount as String: key,
        ]
    }
}
