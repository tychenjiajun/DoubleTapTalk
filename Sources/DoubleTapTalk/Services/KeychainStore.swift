import Foundation
import Security

/// Minimal Keychain string store for secrets (API keys).
///
/// UserDefaults plists are plain text and sync/back up with the machine —
/// credentials must not live there. All operations fail soft (return false /
/// nil) so a Keychain denial (locked keychain, signing/ACL trouble) degrades
/// to "key not stored" instead of crashing the settings UI; the caller keeps
/// a UserDefaults fallback so the app still works.
enum KeychainStore {
    /// Stable service id — a password reset here means losing stored keys,
    /// so it must never change with the bundle id.
    private static let service = "com.jiajun.doubletaptalk.secrets"

    enum Account {
        static let llmAPIKey = "llmAPIKey"
        static let asrAPIKey = "asrAPIKey"
    }

    /// Reads a stored secret, or nil when absent/unreadable.
    static func string(forKey account: String) -> String? {
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

    /// Stores (or removes, when value is nil/empty) a secret.
    /// Returns false when the Keychain rejected the write — the caller is
    /// responsible for its fallback.
    @discardableResult
    static func set(_ value: String?, forKey account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Always delete first: keeps "set" idempotent (add-vs-update is the
        // usual errSecDuplicateItem footgun).
        SecItemDelete(base as CFDictionary)

        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            return true // deletion is the whole job for nil/empty
        }

        var attributes = base
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            FileLogger.shared.error("Keychain write failed for \(account): OSStatus \(status)")
            return false
        }
        return true
    }
}
