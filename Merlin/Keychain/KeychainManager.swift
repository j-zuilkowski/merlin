import Foundation
import Security

enum KeychainManager {

    // MARK: - Per-provider API keys

    /// Keychain service used for all provider API keys.
    private static let apiKeyService = "com.merlin.api-keys"

    /// Flat JSON file used as the primary key store.
    ///
    /// Keychain ACLs are bound to the signing identity of the writing binary. Because
    /// Merlin is ad-hoc signed, every Release and Debug build produces a distinct
    /// identity, so a key written by one build is unreadable by another. The file
    /// store has no such restriction: any process running as the same user can read it.
    /// Keychain is kept as a secondary write target for compatibility with external tools.
    private static let fileStorePath: String = {
        let base = (NSHomeDirectory() as NSString).appendingPathComponent(".merlin")
        return (base as NSString).appendingPathComponent("api-keys.json")
    }()

    // MARK: - Read

    /// Read the stored API key for `providerID`.
    /// File store is checked first (reliable across builds); Keychain is the fallback.
    static func readAPIKey(for providerID: String) -> String? {
        if let key = readFromFile(for: providerID) { return key }
        return readFromKeychain(for: providerID)
    }

    // MARK: - Write

    /// Persist the API key for `providerID`.
    /// Writes to both the file store (primary) and Keychain (secondary, best-effort).
    static func writeAPIKey(_ key: String, for providerID: String) throws {
        try writeToFile(key, for: providerID)
        writeToKeychain(key, for: providerID)   // best-effort; failures are non-fatal
    }

    // MARK: - Delete

    /// Remove the API key for `providerID` from both stores.
    static func deleteAPIKey(for providerID: String) throws {
        try deleteFromFile(for: providerID)
        deleteFromKeychain(for: providerID)     // best-effort
    }

    // MARK: - File store

    private static func loadFileStore() -> [String: String] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fileStorePath)),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        return dict
    }

    private static func saveFileStore(_ dict: [String: String]) throws {
        let dir = (fileStorePath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(dict)
        try data.write(to: URL(fileURLWithPath: fileStorePath), options: .atomic)
    }

    private static func readFromFile(for providerID: String) -> String? {
        loadFileStore()[providerID]
    }

    private static func writeToFile(_ key: String, for providerID: String) throws {
        var store = loadFileStore()
        store[providerID] = key
        try saveFileStore(store)
    }

    private static func deleteFromFile(for providerID: String) throws {
        var store = loadFileStore()
        guard store[providerID] != nil else { return }
        store.removeValue(forKey: providerID)
        try saveFileStore(store)
    }

    // MARK: - Keychain (secondary)

    private static func readFromKeychain(for providerID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
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
            TelemetryEmitter.shared.emit("keychain.read.error", data: [
                "provider": providerID,
                "osstatus": Int(status),
            ])
        }
        return nil
    }

    private static func writeToKeychain(_ key: String, for providerID: String) {
        let data = Data(key.utf8)
        let deleteQuery: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
        ]
        SecItemDelete(deleteQuery as CFDictionary)
        let add: [String: Any] = [
            kSecClass as String:          kSecClassGenericPassword,
            kSecAttrService as String:    apiKeyService,
            kSecAttrAccount as String:    providerID,
            kSecValueData as String:      data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(deleteQuery as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        }
        if status != errSecSuccess {
            TelemetryEmitter.shared.emit("keychain.write.error", data: [
                "provider": providerID, "osstatus": Int(status),
            ])
        }
    }

    private static func deleteFromKeychain(for providerID: String) {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Legacy single-key shims (used by KeychainTests)

    static let service = "com.merlin.deepseek"
    static let account = "api-key"

    static func readAPIKey() -> String? { readAPIKey(for: "deepseek-legacy") }
    static func writeAPIKey(_ key: String) throws { try writeAPIKey(key, for: "deepseek-legacy") }
    static func deleteAPIKey() throws { try deleteAPIKey(for: "deepseek-legacy") }
}
