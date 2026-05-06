import Foundation
import Security

/// Stores API keys in `~/.merlin/api-keys.json` (chmod 0600).
///
/// File-based storage is intentionally chosen over macOS Keychain for keys managed
/// by this app. Ad-hoc rebuilt binaries get a new code-signing identity on every
/// build, which causes Keychain ACL mismatches — the exact problem that `~/.aws/credentials`,
/// `~/.config/gh/hosts.yml`, and similar tools solve by using protected files instead.
/// The file is only readable by the owning user (mode 0600) and lives in `~/.merlin/`
/// which is already the app's config home.
enum KeychainManager {

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
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(keys)
        try data.write(to: keysFileURL, options: .atomic)
        // chmod 0600 — owner read/write only
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keysFileURL.path)
    }

    // MARK: - Per-provider API keys

    static func readAPIKey(for providerID: String) -> String? {
        // Primary: file store
        if let key = loadKeys()[providerID], !key.isEmpty {
            return key
        }
        // Migration fallback: legacy Keychain (one-time read, then re-save to file)
        if let key = readFromKeychain(for: providerID) {
            try? writeAPIKey(key, for: providerID)   // migrate to file
            deleteFromKeychain(for: providerID)       // clean up legacy item
            return key
        }
        return nil
    }

    static func writeAPIKey(_ key: String, for providerID: String) throws {
        var keys = loadKeys()
        keys[providerID] = key
        try saveKeys(keys)
    }

    static func deleteAPIKey(for providerID: String) throws {
        var keys = loadKeys()
        keys.removeValue(forKey: providerID)
        try saveKeys(keys)
    }

    // MARK: - Legacy Keychain read (migration only)

    private static let apiKeyService = "com.merlin.api-keys"

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
