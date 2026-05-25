# Phase 191b — KAG XcalibrePlugin + RAGTools + AppSettings Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 191a complete: failing tests for XcalibreKAGPlugin, KAGEngine extraction, AppSettings
KAG keys, and RAGTools.buildEnrichedMessage.

This phase:
- Implements XcalibreKAGPlugin (REST calls to xcalibre-server graph endpoints)
- Replaces KAGEngine.extractTriples stub with real LLM-gated extraction + parseExtractedTriples
- Adds kagEnabled / kagHops / kagXcalibreURL to AppSettings
- Extends RAGTools.buildEnrichedMessage with graph injection
- Wires startup: AppState.init registers XcalibreKAGPlugin or LocalKAGPlugin based on settings
- Bumps version to 1.7.0

---

## Write to: Merlin/KAG/XcalibreKAGPlugin.swift

```swift
//  XcalibreKAGPlugin.swift — KAGBackendPlugin backed by xcalibre-server REST API.
//
//  Calls:
//    POST /api/v1/graph/triples  (ingest session triples)
//    GET  /api/v1/graph/traverse (BFS traversal)
//
//  All calls use a Bearer token. 10-second timeout. Silent failure is NOT the goal
//  here — callers decide whether to propagate or swallow.

import Foundation

public final class XcalibreKAGPlugin: KAGBackendPlugin, @unchecked Sendable {

    private let baseURL: URL
    private let token:   String
    private let session: URLSession

    public init(baseURL: URL, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token   = token
        self.session = session
    }

    // MARK: - Write

    public func writeTriples(_ triples: [KAGTriple]) async throws {
        guard !triples.isEmpty else { return }

        let url = baseURL.appendingPathComponent("/api/v1/graph/triples")
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let payload = WritePayload(triples: triples.map {
            TripleDTO(subject: $0.subject, predicate: $0.predicate, object: $0.object,
                      domain_id: $0.domainId, session_id: "", confidence: $0.confidence)
        })
        req.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw XcalibreKAGError.badStatus(code)
        }
    }

    // MARK: - Traverse

    public func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/graph/traverse"),
                                       resolvingAgainstBaseURL: false)!
        var items: [URLQueryItem] = [
            .init(name: "anchor", value: anchor),
            .init(name: "hops",   value: "\(hops)"),
        ]
        if let d = domainId, !d.isEmpty {
            items.append(.init(name: "domain_id", value: d))
        }
        components.queryItems = items

        var req = URLRequest(url: components.url!, timeoutInterval: 10)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw XcalibreKAGError.badStatus(code)
        }

        let envelope = try JSONDecoder().decode(TraverseEnvelope.self, from: data)
        return envelope.triples.map {
            KAGTriple(subject: $0.subject, predicate: $0.predicate, object: $0.object,
                      domainId: $0.domain_id,
                      source: KAGTripleSource(rawValue: $0.source) ?? .session,
                      confidence: $0.confidence)
        }
    }

    // MARK: - Codable helpers

    private struct WritePayload: Encodable {
        let triples: [TripleDTO]
    }

    private struct TripleDTO: Encodable {
        let subject:    String
        let predicate:  String
        let object:     String
        let domain_id:  String
        let session_id: String
        let confidence: Double
    }

    private struct TraverseEnvelope: Decodable {
        let triples: [ServerTriple]
    }

    private struct ServerTriple: Decodable {
        let subject:     String
        let predicate:   String
        let object:      String
        let domain_id:   String
        let source:      String
        let confidence:  Double
    }
}

enum XcalibreKAGError: Error {
    case badStatus(Int)
}
```

---

## Edit: Merlin/KAG/KAGEngine.swift

Replace the stub `extractTriples` and add `parseExtractedTriples`.

**Find:** `/// Stub in 190b: returns []. Replaced by LLM extraction in 191b.`
**Replace with the full real implementation:**

```swift
    // MARK: - Extraction (real, LLM-gated)

    /// Calls the active chat provider with a compact extraction prompt.
    /// Returns [] on any error (timeout, bad JSON, no LLM configured).
    func extractTriples(text: String, domain: String) -> [KAGTriple] {
        // Fire-and-forget — callers do not await this.
        // Return is synchronous stub; actual work is in the async helper.
        return []
    }

    /// Async extraction — called from runExtraction.
    func extractTriplesAsync(text: String, domain: String) async -> [KAGTriple] {
        guard let provider = ChatProviderRegistry.shared.current else { return [] }
        let prompt = """
        Extract entity-relationship triples from this text.
        Respond ONLY with a JSON array: [{"subject":"...","predicate":"...","object":"..."}]
        If no clear triples exist, respond with [].
        Domain context: \(domain)
        Text: \(text.prefix(1000))
        """
        do {
            let response = try await withTimeout(seconds: 10) {
                try await provider.complete(prompt: prompt, maxTokens: 256)
            }
            return parseExtractedTriples(json: response, domain: domain)
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

    // MARK: - Private helpers

    private func withTimeout<T: Sendable>(seconds: Double, operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CancellationError()
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
```

**Also update `runExtraction` to call the async version:**

```swift
    private func runExtraction(turn: String, domain: String) async {
        let triples = await extractTriplesAsync(text: turn, domain: domain)
        guard !triples.isEmpty else { return }
        do {
            try await registry.current.writeTriples(triples)
        } catch {
            // Silent failure — never surface to UI.
        }
    }
```

---

## Edit: AppSettings (add KAG keys)

In the file that defines `AppSettings` (likely `Merlin/Settings/AppSettings.swift`):

**Add properties:**
```swift
// MARK: - KAG

/// Whether the knowledge graph extraction and retrieval is active.
@AppSetting("kag_enabled", default: false)
public var kagEnabled: Bool

/// BFS hop depth for graph traversal calls (1–5).
@AppSetting("kag_hops", default: 2)
public var kagHops: Int

/// xcalibre-server base URL for graph endpoints (empty = use LocalKAGPlugin).
@AppSetting("kag_xcalibre_url", default: "")
public var kagXcalibreURL: String
```

If `AppSettings` uses a different persistence pattern (e.g. TOML parsing), add the equivalent keys under the `[kag]` section:
- `enabled` → `kagEnabled`
- `hops`    → `kagHops`
- `xcalibre_url` → `kagXcalibreURL`

---

## Edit: RAGTools (add buildEnrichedMessage)

In `Merlin/RAG/RAGTools.swift` (or wherever `buildEnrichedMessage` / context construction lives):

```swift
/// Builds a context message that combines retrieved chunks with knowledge graph triples.
/// Appends a `## Knowledge Graph` section only when traverse returns non-empty results.
@MainActor
public static func buildEnrichedMessage(
    query: String,
    chunks: [RAGChunk],
    registry: KAGBackendRegistry,
    hops: Int,
    domainId: String?
) async -> String {
    var parts: [String] = []

    if !chunks.isEmpty {
        parts.append("## Retrieved Passages")
        for chunk in chunks {
            parts.append("- [\(chunk.title)] \(chunk.text)")
        }
    }

    let triples = (try? await registry.current.traverse(anchor: query, hops: hops,
                                                         domainId: domainId)) ?? []
    if !triples.isEmpty {
        parts.append("\n## Knowledge Graph")
        for t in triples {
            parts.append("- \(t.subject) \(t.predicate) \(t.object) [\(t.domainId)]")
        }
    }

    return parts.joined(separator: "\n")
}
```

If `RAGChunk` is not the correct type name, use whatever the existing chunk type is.

---

## Edit: AppState.init (startup wiring)

In `AppState` (or `AppDelegate`), after settings are loaded, add:

```swift
// Wire KAG backend
Task { @MainActor in
    if AppSettings.shared.kagEnabled {
        let xcalibreURL = AppSettings.shared.kagXcalibreURL
        if !xcalibreURL.isEmpty, let url = URL(string: xcalibreURL) {
            // XcalibreKAGPlugin requires a token — reuse the stored xcalibre API token.
            let token = AppSettings.shared.xcalibreToken  // adjust key as needed
            let plugin = XcalibreKAGPlugin(baseURL: url, token: token)
            KAGBackendRegistry.shared.register(plugin)
        } else {
            // Fall back to local SQLite graph
            if let plugin = try? LocalKAGPlugin() {
                KAGBackendRegistry.shared.register(plugin)
            }
        }
    }
}
```

---

## Version bump

### Edit: project.yml

```yaml
MARKETING_VERSION: "1.7.0"
CURRENT_PROJECT_VERSION: 7
```

### Edit: constitution.md

```
**Current version: 1.7.0** (build 7, tag `v1.7.0`)
```

---

## Regenerate Xcode project

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|error:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD SUCCEEDED; all 191a tests pass:
- XcalibreKAGPluginTests (4 tests)
- KAGEngineExtractionTests (4 tests)
- AppSettingsKAGTests (5 tests)
- RAGToolsEnrichmentTests (2 tests)

All 190a tests still pass. Zero warnings, zero errors.

---

## Commit and tag

```bash
cd ~/Documents/localProject/merlin
git add \
  Merlin/KAG/XcalibreKAGPlugin.swift \
  Merlin/KAG/KAGEngine.swift \
  Merlin/Settings/AppSettings.swift \
  Merlin/RAG/RAGTools.swift \
  Merlin/AppState.swift \
  project.yml \
  constitution.md \
  Merlin.xcodeproj/project.pbxproj
git commit -m "Phase 191b — KAG XcalibreKAGPlugin + RAGTools enrichment + AppSettings (v1.7.0)"
git tag v1.7.0
git push && git push --tags
```

---

## Release

```bash
gh release create v1.7.0 \
    --repo j-zuilkowski/merlin \
    --title "v1.7.0 — Knowledge-Augmented Generation" \
    --notes "Adds KAG graph layer: LocalKAGPlugin (offline), XcalibreKAGPlugin (xcalibre-server), post-turn triple extraction, enriched RAG context injection." \
    --latest
```
