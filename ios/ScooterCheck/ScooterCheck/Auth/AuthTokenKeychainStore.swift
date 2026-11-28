import Foundation
import Security

/// Secure JWT storage. Migrates a one-time legacy UserDefaults token into Keychain.
protocol AuthTokenStoring: AnyObject {
    func loadToken() -> String?
    func saveToken(_ token: String)
    func deleteToken()
}

enum AuthTokenKeychainStore {
    static let service = "de.tuningscanner.scootercheck.auth"
    static let account = "access_token"
    /// Legacy location before P0 Keychain migration — read once, then cleared.
    static let legacyUserDefaultsKey = "scootercheck.auth.token"
}

final class KeychainAuthTokenStore: AuthTokenStoring {
    private let service: String
    private let account: String
    private let legacyKey: String
    private let defaults: UserDefaults

    init(
        service: String = AuthTokenKeychainStore.service,
        account: String = AuthTokenKeychainStore.account,
        legacyKey: String = AuthTokenKeychainStore.legacyUserDefaultsKey,
        defaults: UserDefaults = .standard
    ) {
        self.service = service
        self.account = account
        self.legacyKey = legacyKey
        self.defaults = defaults
    }

    func loadToken() -> String? {
        if let existing = readKeychain() {
            return existing
        }
        // One-shot migration from UserDefaults → Keychain.
        guard let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty else {
            return nil
        }
        saveToken(legacy)
        defaults.removeObject(forKey: legacyKey)
        return legacy
    }

    func saveToken(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        // Ensure legacy plaintext copy is gone after any save attempt.
        defaults.removeObject(forKey: legacyKey)
        // Agent C: never ignore Keychain write failures (silent drop → phantom logout).
        if status != errSecSuccess {
            assertionFailure("Keychain SecItemAdd failed: \(status)")
        }
    }

    func deleteToken() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        defaults.removeObject(forKey: legacyKey)
    }

    private func readKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// In-memory token store for unit tests (no Keychain / Security dependency).
final class InMemoryAuthTokenStore: AuthTokenStoring {
    private var token: String?
    private let legacyKey: String
    private let defaults: UserDefaults

    init(legacyKey: String = AuthTokenKeychainStore.legacyUserDefaultsKey, defaults: UserDefaults = .standard) {
        self.legacyKey = legacyKey
        self.defaults = defaults
    }

    func loadToken() -> String? {
        if let token { return token }
        guard let legacy = defaults.string(forKey: legacyKey), !legacy.isEmpty else { return nil }
        token = legacy
        defaults.removeObject(forKey: legacyKey)
        return legacy
    }

    func saveToken(_ token: String) {
        self.token = token
        defaults.removeObject(forKey: legacyKey)
    }

    func deleteToken() {
        token = nil
        defaults.removeObject(forKey: legacyKey)
    }
}
