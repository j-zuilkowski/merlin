import Foundation

enum RAGSelector {
    static func selectChunks(
        candidates: [RAGChunk],
        budget: Int,
        userCeiling: Int
    ) -> [RAGChunk] {
        guard budget >= 0, userCeiling > 0, candidates.isEmpty == false else { return [] }

        var selected: [RAGChunk] = []
        selected.reserveCapacity(min(candidates.count, userCeiling))
        var tokensUsed = 0

        for chunk in candidates {
            guard selected.count < userCeiling else { break }

            let chunkTokens = TokenEstimator.estimateText(chunk.text)
            if tokensUsed + chunkTokens > budget {
                break
            }

            selected.append(chunk)
            tokensUsed += chunkTokens
        }

        return selected
    }
}
