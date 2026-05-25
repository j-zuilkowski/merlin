import Foundation
import Security

/// Stores provider API keys.
///
/// Debug builds use `~/.merlin/api-keys.json` (chmod 0600) to avoid Keychain ACL churn
/// during ad-hoc rebuild loops. Release builds use macOS Keychain.
enum KeychainManager {

    #if DEBUG
    static let usesFileBackedStorage = true
    #else
    static let usesFileBackedStorage = false
    #endif

    static var storageDescription: String {
        usesFileBackedStorage
            ? "~/.merlin/api-keys.json (0600, Debug builds)"
            : "macOS Keychain (Release builds)"
    }

    // MARK: - File-based storage

    private static var keysFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".merlin/api-keys.json")
    }

    private static func loadKeys() -> [String: String] {
        guard let data = try? Data(contentsOf: keysFileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return [:]
        }
        return dict
    }

    private static func saveKeys(_ keys: [String: String]) throws {
        let dir = keysFileURL.deletingLastPathComponent()
        if keys.isEmpty {
            try? FileManager.default.removeItem(at: keysFileURL)
            return
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(keys)
        try data.write(to: keysFileURL, options: .atomic)
        // chmod 0600 — owner read/write only
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keysFileURL.path)
    }

    // MARK: - Per-provider API keys

    static func readAPIKey(for providerID: String) -> String? {
        if usesFileBackedStorage {
            if let key = loadKeys()[providerID], !key.isEmpty {
                return key
            }
            if let key = readFromKeychain(for: providerID) {
                try? writeAPIKey(key, for: providerID)
                deleteFromKeychain(for: providerID)
                return key
            }
            return nil
        }

        if let key = readFromKeychain(for: providerID) {
            return key
        }
        if let key = loadKeys()[providerID], !key.isEmpty {
            try? writeToKeychain(key, for: providerID)
            try? deleteFromFile(for: providerID)
            return key
        }
        return nil
    }

    static func writeAPIKey(_ key: String, for providerID: String) throws {
        if !usesFileBackedStorage {
            try writeToKeychain(key, for: providerID)
            try? deleteFromFile(for: providerID)
            return
        }
        var keys = loadKeys()
        keys[providerID] = key
        try saveKeys(keys)
    }

    static func deleteAPIKey(for providerID: String) throws {
        deleteFromKeychain(for: providerID)
        try deleteFromFile(for: providerID)
    }

    private static func deleteFromFile(for providerID: String) throws {
        var keys = loadKeys()
        keys.removeValue(forKey: providerID)
        try saveKeys(keys)
    }

    // MARK: - Legacy Keychain read (migration only)

    private static let apiKeyService = "com.merlin.api-keys"

    private static func writeToKeychain(_ key: String, for providerID: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(updateStatus))
        }

        var add = query
        add[kSecValueData as String] = data
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
        }
    }

    private static func readFromKeychain(for providerID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: apiKeyService,
            kSecAttrAccount as String: providerID,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
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
