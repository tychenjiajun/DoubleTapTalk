import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()
    
    private let serviceName = "com.jiajun.doubletaptalk.app"
    private let logger = FileLogger.shared
    
    private func accountKey(for backend: ASRBackendType) -> String {
        return "apikey.\(backend.rawValue)"
    }
    
    func saveAPIKey(_ apiKey: String, for backend: ASRBackendType) {
        let account = accountKey(for: backend)
        logger.debug("Saving API key for backend: \(backend.rawValue)")
        
        // Delete existing key first
        deleteAPIKey(for: backend)
        
        let data = apiKey.data(using: .utf8)!
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        if status != errSecSuccess {
            logger.error("Keychain save error for \(backend.rawValue): \(status)")
        } else {
            logger.info("API key saved successfully for \(backend.rawValue)")
        }
    }
    
    func getAPIKey(for backend: ASRBackendType) -> String? {
        let account = accountKey(for: backend)
        logger.debug("Retrieving API key for backend: \(backend.rawValue)")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            logger.debug("No API key found for \(backend.rawValue)")
            return nil
        }
        
        logger.debug("API key retrieved for \(backend.rawValue)")
        return apiKey
    }
    
    func deleteAPIKey(for backend: ASRBackendType) {
        let account = accountKey(for: backend)
        logger.debug("Deleting API key for backend: \(backend.rawValue)")
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        if status == errSecSuccess {
            logger.debug("API key deleted for \(backend.rawValue)")
        } else if status != errSecItemNotFound {
            logger.warning("Failed to delete API key for \(backend.rawValue): \(status)")
        }
    }
    

}