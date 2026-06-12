import Foundation

final class WebSearchCache<Value: Sendable>: @unchecked Sendable {
    private struct Entry {
        var value: Value
        var expiresAt: Date
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let clock: any ClockProvider

    init(clock: any ClockProvider = SystemClock()) {
        self.clock = clock
    }

    func value(for key: String) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > clock.now() else {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.value
    }

    func store(_ value: Value, for key: String, ttlSeconds: Int) {
        guard ttlSeconds > 0 else { return }
        lock.lock()
        entries[key] = Entry(value: value, expiresAt: clock.now().addingTimeInterval(TimeInterval(ttlSeconds)))
        lock.unlock()
    }

    func clear() {
        lock.lock()
        entries.removeAll()
        lock.unlock()
    }
}

enum WebSearchGlobalCaches {
    static let search = WebSearchCache<SearchResponse>()
}

enum WebSearchCacheKey {
    static let searchVersion = "search-v2"
    static let extractionVersion = "extract-v1"

    static func search(request: SearchRequest, settings: WebSearchSettings, providerIDs: [String]) -> String {
        [
            searchVersion,
            "q=\(request.query)",
            "locale=\(request.locale ?? "")",
            "freshness=\(request.freshnessHint ?? "")",
            "count=\(request.count ?? settings.maxMergedResults)",
            "providers=\(providerIDs.sorted().joined(separator: ","))",
            "order=\(settings.providerOrder.joined(separator: ","))",
            "perProvider=\(settings.maxResultsPerProvider)",
            "allowed=\(request.allowedDomains.sorted().joined(separator: ","))",
            "blocked=\(request.blockedDomains.sorted().joined(separator: ","))",
        ].joined(separator: "|")
    }

    static func extraction(url: String, settings: WebSearchSettings, strategy: String) -> String {
        [
            extractionVersion,
            "url=\(URLCanonicalizer.canonicalize(url))",
            "strategy=\(strategy)",
            "bytes=\(settings.extractionMaxBytes)",
            "bot=\(settings.botPolicyMode.rawValue)",
            "webkit=\(settings.webkitExtractionEnabled)",
        ].joined(separator: "|")
    }
}
