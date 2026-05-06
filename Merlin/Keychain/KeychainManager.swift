import Foundation
import Security

enum KeychainManager {

    // MARK: - Per-provider API keys

    /// Keychain service used for all provider API keys.
    private static let apiKeyService = "com.merlin.api-keys"

    /// Read the stored API key for `providerID` (e.g. `"deepseek"`, `"anthropic"`).
    ///
    /// Tries the Data Protection Keychain first (modern, user-scoped, rebuild-safe).
    /// Falls back to the legacy file-based keychain for items written by older builds,
    /// and migrates them to the Data Protection Keychain on first read.
    static func readAPIKey(for providerID: String) -> String? {
        // 1. Try modern Data Protection Keychain
        if let key = readRaw(providerID: providerID, dataProtection: true) {
            return key
        }
        // 2. Fall back to legacy file-based keychain and migrate if found
        if let key = readRaw(providerID: providerID, dataProtection: false) {
            try? writeAPIKey(key, for: providerID) // migrate to Data Protection Keychain
            return key
        }
        return nil
    }

    private static func readRaw(providerID: String, dataProtection: Bool) -> String? {
        var query: [String: Any] = [
            kSecClass as String:                  kSecClassGenericPassword,
            kSecAttrService as String:            apiKeyService,
            kSecAttrAccount as String:            providerID,
            kSecReturnData as String:             true,
            kSecMatchLimit as String:             kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: dataProtection,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        if status != errSecItemNotFound && status != errSecUserCanceled {
            TelemetryEmitter.shared.emit("keychain.read.error", data: [
                "provider": providerID,
                "dataProtection": dataProtection,
                "osstatus": Int(status),
            ])
        }
        return nil
    }

    /// Persist the API key for `providerID`.
    ///
    /// Writes exclusively to the Data Protection Keychain with
    /// `kSecAttrAccessibleAfterFirstUnlock`. Items in the Data Protection Keychain
    /// are user-scoped, not app-signing-identity-scoped — they survive rebuilds,
    /// ad-hoc re-signing, and reinstalls without requiring the user to re-enter keys.
    static func writeAPIKey(_ key: String, for providerID: String) throws {
        let data = Data(key.utf8)

        // Delete from both keychains so no stale legacy item blocks a future read.
        for dataProtection in [true, false] {
            let deleteQuery: [String: Any] = [
                kSecClass as String:                     kSecClassGenericPassword,
                kSecAttrService as String:               apiKeyService,
                kSecAttrAccount as String:               providerID,
                kSecUseDataProtectionKeychain as String: dataProtection,
            ]
            SecItemDelete(deleteQuery as CFDictionary)
        }

        let add: [String: Any] = [
            kSecClass as String:                     kSecClassGenericPassword,
            kSecAttrService as String:               apiKeyService,
            kSecAttrAccount as String:               providerID,
            kSecValueData as String:                 data,
            kSecAttrAccessible as String:            kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true,
        ]

        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    /// Remove the API key for `providerID` from both keychains. Silent no-op if not found.
    static func deleteAPIKey(for providerID: String) throws {
        for dataProtection in [true, false] {
            let query: [String: Any] = [
                kSecClass as String:                     kSecClassGenericPassword,
                kSecAttrService as String:               apiKeyService,
                kSecAttrAccount as String:               providerID,
                kSecUseDataProtectionKeychain as String: dataProtection,
            ]
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
            }
        }
    }

    // MARK: - Legacy single-key shims (used by KeychainTests)

    static let service = "com.merlin.deepseek"
    static let account = "api-key"

    static func readAPIKey() -> String? { readAPIKey(for: "deepseek-legacy") }
    static func writeAPIKey(_ key: String) throws { try writeAPIKey(key, for: "deepseek-legacy") }
    static func deleteAPIKey() throws { try deleteAPIKey(for: "deepseek-legacy") }
}
