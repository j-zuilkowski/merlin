import Foundation

enum ManagedProviderCredentials {
    static func apiKey(settingsValue: String?, environmentKey: String) -> String? {
        if let settingsValue, !settingsValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return settingsValue
        }
        let value = ProcessInfo.processInfo.environment[environmentKey] ?? ""
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : value
    }
}
