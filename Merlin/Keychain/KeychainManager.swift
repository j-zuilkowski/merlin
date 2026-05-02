import Foundation
import Security

enum KeychainManager {

    // MARK: - Per-provider API keys

    /// Keychain service used for all provider API keys.
    private static let apiKeyService = "com.merlin.api-keys"

    /// Read the stored API key for `providerID` (e.g. `"deepseek"`, `"anthropic"`).
    static func readAPIKey(for providerID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8)
        else { return nil }
        return key
    }

    /// Persist (or update) the API key for `providerID`.
    static func writeAPIKey(_ key: String, for providerID: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
        ]
        let status = SecItemUpdate(query as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
            return
        }
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    /// Remove the API key for `providerID`. Silent no-op if not found.
    static func deleteAPIKey(for providerID: String) throws {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    // MARK: - Legacy single-key shims (used by KeychainTests)

    static let service = "com.merlin.deepseek"
    static let account = "api-key"

    static func readAPIKey() -> String? { readAPIKey(for: "deepseek-legacy") }
    static func writeAPIKey(_ key: String) throws { try writeAPIKey(key, for: "deepseek-legacy") }
    static func deleteAPIKey() throws { try deleteAPIKey(for: "deepseek-legacy") }
}
