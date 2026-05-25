import Foundation

struct CAGCacheUsage: Sendable, Equatable, Codable {
    var readTokens: Int
    var creationTokens: Int
    var uncachedInputTokens: Int

    var hitRate: Double {
        let total = max(1, readTokens + creationTokens + uncachedInputTokens)
        return Double(readTokens) / Double(total)
    }

    static let zero = CAGCacheUsage(readTokens: 0, creationTokens: 0, uncachedInputTokens: 0)
}

actor CAGCacheMetricsStore {
    static let shared = CAGCacheMetricsStore()

    private var usageByProviderID: [String: CAGCacheUsage] = [:]

    func record(_ usage: CAGCacheUsage, providerID: String) {
        let current = usageByProviderID[providerID] ?? .zero
        usageByProviderID[providerID] = CAGCacheUsage(
            readTokens: current.readTokens + usage.readTokens,
            creationTokens: current.creationTokens + usage.creationTokens,
            uncachedInputTokens: current.uncachedInputTokens + usage.uncachedInputTokens
        )
    }

    func snapshot(providerID: String) -> CAGCacheUsage {
        usageByProviderID[providerID] ?? .zero
    }

    func reset(providerID: String) {
        usageByProviderID[providerID] = .zero
    }
}
