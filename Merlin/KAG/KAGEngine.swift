//  KAGEngine.swift — post-turn idle-timer triple extraction.
//
//  After each assistant turn, the engine waits 2 seconds (idle timer) then calls
//  extractTriplesAsync(text:domain:), which calls the active LLM provider to produce
//  a JSON triple array and writes the results to the registered KAGBackendPlugin.
//
//  providerFactory is wired by AppState.configureKAGBackend() at startup.
//  Returns (provider, modelID). If nil, extraction is silently skipped.

import Foundation

@MainActor
public final class KAGEngine {

    // Process-wide singleton.
    public static let shared = KAGEngine(registry: .shared)

    private let registry: KAGBackendRegistry
    private var pendingTask: Task<Void, Never>?

    /// Set by AppState at startup. Returns the active LLM provider and its model ID.
    /// When nil, extraction is a no-op (no LLM configured or KAG disabled).
    var providerFactory: (() -> (any LLMProvider, String)?)?

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

    /// Calls the active LLM provider with a compact extraction prompt.
    /// Streams the response, collects text, then parses the JSON triple array.
    /// Returns [] silently on any failure (no provider, timeout, bad JSON).
    func extractTriplesAsync(text: String, domain: String) async -> [KAGTriple] {
        guard let (provider, model) = providerFactory?() else { return [] }

        let systemPrompt = "You extract entity-relationship triples from text. " +
            "Respond ONLY with a JSON array: " +
            "[{\"subject\":\"...\",\"predicate\":\"...\",\"object\":\"...\"}]. " +
            "If no clear triples exist, respond with []."

        let request = CompletionRequest(
            model: model,
            messages: [
                Message(role: .system,
                        content: .text(systemPrompt),
                        timestamp: Date()),
                Message(role: .user,
                        content: .text("Domain: \(domain)\n\nText: \(text.prefix(1000))"),
                        timestamp: Date()),
            ],
            maxTokens: 256,
            temperature: 0.0
        )

        do {
            let stream = try await provider.complete(request: request)
            var collected = ""
            for try await chunk in stream {
                collected += chunk.delta?.content ?? ""
            }
            return parseExtractedTriples(
                json: collected.trimmingCharacters(in: .whitespacesAndNewlines),
                domain: domain
            )
        } catch {
            return []
        }
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
