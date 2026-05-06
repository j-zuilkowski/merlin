import Foundation
import Security

enum KeychainManager {

    // MARK: - Per-provider API keys

    /// Keychain service used for all provider API keys.
    private static let apiKeyService = "com.merlin.api-keys"

    /// Read the stored API key for `providerID` (e.g. `"deepseek"`, `"anthropic"`).
    ///
    /// Returns nil if no key is stored. Logs a telemetry event (non-fatal) when
    /// the Keychain returns any error other than errSecItemNotFound.
    static func readAPIKey(for providerID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        if status != errSecItemNotFound {
            TelemetryEmitter.shared.emit("keychain.read.error", data: [
                "provider": providerID,
                "osstatus": Int(status),
            ])
        }
        return nil
    }

    /// Persist the API key for `providerID`.
    ///
    /// Stores with `kSecAttrAccessibleAfterFirstUnlock` and no application-specific
    /// ACL (`kSecAttrAccess` / `SecAccessCreate` are intentionally omitted).
    /// This means any process running as this user can read the item — no code-signing
    /// identity check, no cdhash binding — so keys survive rebuilds and ad-hoc
    /// re-signing without requiring the user to re-enter them.
    static func writeAPIKey(_ key: String, for providerID: String) throws {
        let data = Data(key.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
        ]
        // Delete any existing item (regardless of who wrote it).
        SecItemDelete(deleteQuery as CFDictionary)

        let add: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    apiKeyService,
            kSecAttrAccount as String:    providerID,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        var addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            addStatus = SecItemUpdate(deleteQuery as CFDictionary,
                                      [kSecValueData as String: data] as CFDictionary)
        }
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
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
