import Foundation

struct ResultRanker: Sendable {
    func rank(_ results: [SearchResult], query: String, providerOrder: [String], maxResults: Int) -> [SearchResult] {
        let order = Dictionary(uniqueKeysWithValues: providerOrder.enumerated().map { ($0.element, $0.offset) })
        let duplicateCounts = Dictionary(grouping: results, by: \.canonicalURL).mapValues(\.count)
        let scored = results.map { result in
            RankedResult(
                result: result,
                score: deterministicScore(
                    result,
                    query: query,
                    providerOrder: order,
                    duplicateCount: duplicateCounts[result.canonicalURL] ?? 1
                )
            )
        }
        var bestByURL: [String: RankedResult] = [:]
        for item in scored {
            guard let existing = bestByURL[item.result.canonicalURL] else {
                bestByURL[item.result.canonicalURL] = item
                continue
            }
            if shouldPrefer(item, over: existing, providerOrder: order) {
                bestByURL[item.result.canonicalURL] = item
            }
        }
        let deduped = bestByURL.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return shouldPrefer($0, over: $1, providerOrder: order)
        }.map(\.result)
        return deduped.prefix(maxResults).enumerated().map { index, result in
            var copy = result
            copy.rank = index + 1
            return copy
        }
    }

    private func deterministicScore(
        _ result: SearchResult,
        query: String,
        providerOrder: [String: Int],
        duplicateCount: Int
    ) -> Double {
        let tokens = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let title = result.title.lowercased()
        let snippet = result.snippet.lowercased()
        let matchedTitle = tokens.filter { title.contains($0) }.count
        let matchedSnippet = tokens.filter { snippet.contains($0) }.count
        let providerOffset = Double(providerOrder[result.providerID] ?? providerOrder.count)
        let domainScore = Self.domainQualityScore(for: result.canonicalURL)
        let freshnessScore = max(0, min(1, 1 - Date().timeIntervalSince(result.retrievedAt) / (86400 * 365)))
        return result.score
            + Double(matchedTitle) * 8
            + Double(matchedSnippet) * 3
            + Double(max(0, duplicateCount - 1)) * 6
            + domainScore
            + freshnessScore
            - providerOffset * 0.2
            - Double(max(0, result.rank - 1)) * 0.05
    }

    private func shouldPrefer(_ lhs: RankedResult, over rhs: RankedResult, providerOrder: [String: Int]) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        let leftOrder = providerOrder[lhs.result.providerID] ?? Int.max
        let rightOrder = providerOrder[rhs.result.providerID] ?? Int.max
        if leftOrder != rightOrder { return leftOrder < rightOrder }
        return lhs.result.rank < rhs.result.rank
    }

    private static func domainQualityScore(for urlString: String) -> Double {
        guard let host = URL(string: urlString)?.host()?.lowercased() else { return 0 }
        if host.hasSuffix(".gov") || host.hasSuffix(".edu") { return 4 }
        if host == "github.com" || host.hasSuffix(".wikipedia.org") || host.hasSuffix("stackoverflow.com") { return 3 }
        if host.hasPrefix("docs.") || host.contains(".docs.") { return 2 }
        return 0
    }
}

private struct RankedResult {
    var result: SearchResult
    var score: Double
}
