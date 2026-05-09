//  KAGEngine.swift — post-turn idle-timer triple extraction.
//
//  After each assistant turn, the engine waits 2 seconds (idle timer) then calls
//  extractTriples(text:domain:). In phase 190b the extractor is stubbed to return [].
//  Phase 191b replaces the stub with a real LLM call.

import Foundation

@MainActor
public final class KAGEngine {

    // Process-wide singleton.
    public static let shared = KAGEngine(registry: .shared)

    private let registry: KAGBackendRegistry
    private var pendingTask: Task<Void, Never>?

    public init(registry: KAGBackendRegistry) {
        self.registry = registry
    }

    /// Call after each assistant turn. Cancels any pending extraction and restarts the timer.
    public func scheduleExtraction(from turn: String, domain: String) {
        pendingTask?.cancel()
        pendingTask = Task { [weak self] in
            guard let self else { return }
            do {
                // 2-second idle delay — gives time for follow-up messages to cancel.
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return // Task was cancelled
            }
            guard !Task.isCancelled else { return }
            await self.runExtraction(turn: turn, domain: domain)
        }
    }

    // MARK: - Private

    private func runExtraction(turn: String, domain: String) async {
        let triples = await extractTriplesAsync(text: turn, domain: domain)
        guard !triples.isEmpty else { return }
        do {
            try await registry.current.writeTriples(triples)
        } catch {
            // Silent failure — never surface to UI.
        }
    }

    /// Stub in 190b: returns []. Replaced by LLM extraction in 191b.
    func extractTriples(text: String, domain: String) -> [KAGTriple] {
        return []
    }

    /// Async extraction hook. Uses the synchronous stub for now, then normalizes via JSON parsing.
    func extractTriplesAsync(text: String, domain: String) async -> [KAGTriple] {
        let json = extractTriples(text: text, domain: domain)
        guard !json.isEmpty else { return [] }
        guard let data = try? JSONEncoder().encode(json),
              let string = String(data: data, encoding: .utf8) else {
            return []
        }
        return parseExtractedTriples(json: string, domain: domain)
    }

    /// Parse a JSON string like `[{"subject":"A","predicate":"b","object":"C"}]`
    /// into KAGTriple array. Returns [] on any parse failure.
    func parseExtractedTriples(json: String, domain: String) -> [KAGTriple] {
        guard !json.isEmpty,
              let data = json.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [[String: String]]
        else { return [] }

        return array.compactMap { dict in
            guard let subject   = dict["subject"],   !subject.isEmpty,
                  let predicate = dict["predicate"], !predicate.isEmpty,
                  let object    = dict["object"],    !object.isEmpty
            else { return nil }
            return KAGTriple(subject: subject, predicate: predicate, object: object,
                             domainId: domain, source: .session, confidence: 1.0)
        }
    }
}
