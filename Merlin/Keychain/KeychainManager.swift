import Foundation
import Security

enum KeychainManager {

    // MARK: - Per-provider API keys

    /// Keychain service used for all provider API keys.
    private static let apiKeyService = "com.merlin.api-keys"

    /// Read the stored API key for `providerID` (e.g. `"deepseek"`, `"anthropic"`).
    ///
    /// Returns nil if no key is stored. Logs a telemetry event (non-fatal) when
    /// the Keychain returns any error other than errSecItemNotFound — this catches
    /// ACL-mismatch failures from differently-signed builds that would otherwise
    /// silently appear as "no key configured".
    static func readAPIKey(for providerID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
            // Allow the system to present an authentication dialog if the item's
            // ACL requires it (older items written by a differently-signed build).
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIAllow,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess,
           let data = result as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }
        if status != errSecItemNotFound {
            // Emit non-fatal telemetry so the failure is visible in logs.
            TelemetryEmitter.shared.emit("keychain.read.error", data: [
                "provider": providerID,
                "osstatus": Int(status),
            ])
        }
        return nil
    }

    /// Persist the API key for `providerID`.
    ///
    /// Deletes any existing item before adding so the new item's ACL is owned by
    /// the current build. Uses `kSecAttrAccessibleAfterFirstUnlock` so the key
    /// survives sleep/wake without requiring an unlock prompt.
    static func writeAPIKey(_ key: String, for providerID: String) throws {
        let data = Data(key.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
        ]
        // Delete first — resets ACL ownership to the current build. Ignore errSecItemNotFound.
        SecItemDelete(deleteQuery as CFDictionary)

        let add: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      apiKeyService,
            kSecAttrAccount as String:      providerID,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock,
        ]
        let addStatus = SecItemAdd(add as CFDictionary, nil)
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
