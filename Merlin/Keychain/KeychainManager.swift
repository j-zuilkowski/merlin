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
            // Suppress any authentication UI — items written by this app use an
            // unrestricted ACL and should never require a confirmation dialog.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
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
    /// Writes an item with an unrestricted `SecAccess` (nil trusted-applications list).
    /// On macOS, passing nil to SecAccessCreate means "any application can read this
    /// item without prompting" — no per-app ACL check, no cdhash requirement, no
    /// Keychain confirmation dialogs on every launch. This is appropriate for API keys
    /// that are already bound to the user's OS login session.
    static func writeAPIKey(_ key: String, for providerID: String) throws {
        let data = Data(key.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
        ]
        // Delete any existing item (regardless of who owns its ACL).
        SecItemDelete(deleteQuery as CFDictionary)

        // Build an unrestricted SecAccess: nil trusted-apps = any app, no prompt.
        var access: SecAccess?
        SecAccessCreate(apiKeyService as CFString, nil, &access)

        var add: [String: Any] = [
            kSecClass as String:            kSecClassGenericPassword,
            kSecAttrService as String:      apiKeyService,
            kSecAttrAccount as String:      providerID,
            kSecValueData as String:        data,
            kSecAttrAccessible as String:   kSecAttrAccessibleAfterFirstUnlock,
        ]
        if let access { add[kSecAttrAccess as String] = access }

        var addStatus = SecItemAdd(add as CFDictionary, nil)
        if addStatus == errSecDuplicateItem {
            // Shouldn't reach here after the delete above, but guard defensively.
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
