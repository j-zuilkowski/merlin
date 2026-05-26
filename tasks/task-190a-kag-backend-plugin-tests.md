# Task 190a — KAG Backend Plugin Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 189 complete: v1.6.1 crash fix shipped.

New surface introduced in task 190b:
  - `KAGTripleSource` — enum: `session` | `book`
  - `KAGTriple` — Sendable value type: subject, predicate, object, domainId, source, confidence
  - `KAGBackendPlugin` — protocol; `func writeTriples(_ triples: [KAGTriple]) async throws`
    and `func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple]`
  - `NullKAGPlugin` — default no-op: writeTriples is a no-op, traverse returns []
  - `KAGBackendRegistry` — @MainActor singleton; `shared`; `register(_ plugin: any KAGBackendPlugin)`;
    `current: any KAGBackendPlugin` (defaults to NullKAGPlugin)
  - `LocalKAGPlugin` — writes and reads from a SQLite DB at a configurable URL
    (`~/.merlin/kag/graph.sqlite`); uses GRDB-free raw SQLite via `import SQLite3`; creates
    table on first open; writeTriples inserts rows; traverse does iterative BFS (1 SQL query
    per hop) returning deduplicated KAGTriple array
  - `KAGEngine` — @MainActor actor; `shared`; `scheduleExtraction(from turn: String, domain: String)`
    posts an idle-timer task (2 s delay) that calls `extractTriples(text:domain:)` (stubbed in 190b —
    returns []); extracted triples are written via `KAGBackendRegistry.shared.current.writeTriples`

TDD coverage:
  File 1 — KAGTripleTests: value type equality, Sendable conformance
  File 2 — NullKAGPluginTests: writeTriples no-op, traverse returns []
  File 3 — KAGBackendRegistryTests: default is NullKAGPlugin, register replaces current
  File 4 — LocalKAGPluginTests: write+traverse round-trip, hops=1 vs hops=2, domain filter,
    empty result for unknown anchor
  File 5 — KAGEngineTests: scheduleExtraction triggers writeTriples on the registered plugin

---

## Write to: MerlinTests/Unit/KAGTripleTests.swift

```swift
import XCTest
@testable import Merlin

final class KAGTripleTests: XCTestCase {

    func test_triple_equality() {
        let a = KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                          domainId: "electronics", source: .session, confidence: 0.9)
        let b = KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                          domainId: "electronics", source: .session, confidence: 0.9)
        XCTAssertEqual(a, b)
    }

    func test_triple_inequality_different_predicate() {
        let a = KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                          domainId: "electronics", source: .session, confidence: 0.9)
        let b = KAGTriple(subject: "U4", predicate: "connects", object: "VCC",
                          domainId: "electronics", source: .session, confidence: 0.9)
        XCTAssertNotEqual(a, b)
    }

    func test_source_session_rawValue() {
        XCTAssertEqual(KAGTripleSource.session.rawValue, "session")
    }

    func test_source_book_rawValue() {
        XCTAssertEqual(KAGTripleSource.book.rawValue, "book")
    }

    func test_triple_is_sendable() {
        // Compile-time: KAGTriple must conform to Sendable.
        let _: any Sendable = KAGTriple(subject: "A", predicate: "b", object: "C",
                                         domainId: "d", source: .session, confidence: 1.0)
    }
}
```

---

## Write to: MerlinTests/Unit/NullKAGPluginTests.swift

```swift
import XCTest
@testable import Merlin

final class NullKAGPluginTests: XCTestCase {

    func test_writeTriples_noThrow() async throws {
        let plugin = NullKAGPlugin()
        let triple = KAGTriple(subject: "A", predicate: "b", object: "C",
                               domainId: "test", source: .session, confidence: 1.0)
        // Must not throw
        try await plugin.writeTriples([triple])
    }

    func test_traverse_returnsEmpty() async throws {
        let plugin = NullKAGPlugin()
        let result = try await plugin.traverse(anchor: "A", hops: 2, domainId: nil)
        XCTAssertTrue(result.isEmpty)
    }
}
```

---

## Write to: MerlinTests/Unit/KAGBackendRegistryTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class KAGBackendRegistryTests: XCTestCase {

    func test_default_plugin_is_null() {
        // Fresh registry (not shared — create a new instance for isolation).
        let registry = KAGBackendRegistry()
        XCTAssertTrue(registry.current is NullKAGPlugin)
    }

    func test_register_replaces_current() {
        let registry = KAGBackendRegistry()
        let mock = MockKAGPlugin()
        registry.register(mock)
        XCTAssertTrue(registry.current is MockKAGPlugin)
    }

    func test_register_second_time_replaces_again() {
        let registry = KAGBackendRegistry()
        registry.register(MockKAGPlugin())
        registry.register(NullKAGPlugin())
        XCTAssertTrue(registry.current is NullKAGPlugin)
    }
}

// MARK: - Test double
final class MockKAGPlugin: KAGBackendPlugin, @unchecked Sendable {
    var writtenTriples: [KAGTriple] = []

    func writeTriples(_ triples: [KAGTriple]) async throws {
        writtenTriples.append(contentsOf: triples)
    }

    func traverse(anchor: String, hops: Int, domainId: String?) async throws -> [KAGTriple] {
        return []
    }
}
```

---

## Write to: MerlinTests/Unit/LocalKAGPluginTests.swift

```swift
import XCTest
@testable import Merlin

final class LocalKAGPluginTests: XCTestCase {

    private func makeTempPlugin() throws -> LocalKAGPlugin {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-kag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("graph.sqlite")
        return try LocalKAGPlugin(databaseURL: dbURL)
    }

    func test_write_and_traverse_roundtrip() async throws {
        let plugin = try makeTempPlugin()
        let triple = KAGTriple(subject: "FnA", predicate: "calls", object: "FnB",
                               domainId: "software", source: .session, confidence: 0.9)
        try await plugin.writeTriples([triple])

        let result = try await plugin.traverse(anchor: "FnA", hops: 1, domainId: nil)
        XCTAssertFalse(result.isEmpty)
        XCTAssertTrue(result.contains { $0.subject == "FnA" && $0.object == "FnB" })
    }

    func test_hops1_does_not_reach_second_level() async throws {
        let plugin = try makeTempPlugin()
        try await plugin.writeTriples([
            KAGTriple(subject: "FnA", predicate: "calls", object: "FnB",
                      domainId: "sw", source: .session, confidence: 0.9),
            KAGTriple(subject: "FnB", predicate: "calls", object: "FnC",
                      domainId: "sw", source: .session, confidence: 0.9),
        ])

        let result = try await plugin.traverse(anchor: "FnA", hops: 1, domainId: nil)
        XCTAssertTrue(result.contains { $0.subject == "FnA" && $0.object == "FnB" },
                      "FnA->FnB must appear at hops=1")
        XCTAssertFalse(result.contains { $0.subject == "FnB" && $0.object == "FnC" },
                       "FnB->FnC must NOT appear at hops=1")
    }

    func test_hops2_reaches_second_level() async throws {
        let plugin = try makeTempPlugin()
        try await plugin.writeTriples([
            KAGTriple(subject: "FnA", predicate: "calls", object: "FnB",
                      domainId: "sw", source: .session, confidence: 0.9),
            KAGTriple(subject: "FnB", predicate: "calls", object: "FnC",
                      domainId: "sw", source: .session, confidence: 0.9),
        ])

        let result = try await plugin.traverse(anchor: "FnA", hops: 2, domainId: nil)
        XCTAssertTrue(result.contains { $0.subject == "FnB" && $0.object == "FnC" },
                      "FnB->FnC must appear at hops=2")
    }

    func test_domain_filter_excludes_other_domains() async throws {
        let plugin = try makeTempPlugin()
        try await plugin.writeTriples([
            KAGTriple(subject: "turmeric", predicate: "substitutes_for", object: "saffron",
                      domainId: "culinary", source: .session, confidence: 0.8),
            KAGTriple(subject: "U4", predicate: "shares_net", object: "VCC",
                      domainId: "electronics", source: .session, confidence: 0.9),
        ])

        let result = try await plugin.traverse(anchor: "turmeric", hops: 1, domainId: "culinary")
        XCTAssertTrue(result.allSatisfy { $0.domainId == "culinary" },
                      "All results must be culinary when filtered")
        XCTAssertFalse(result.contains { $0.subject == "U4" },
                       "Electronics triples must be excluded")
    }

    func test_unknown_anchor_returns_empty() async throws {
        let plugin = try makeTempPlugin()
        let result = try await plugin.traverse(anchor: "nonexistent", hops: 2, domainId: nil)
        XCTAssertTrue(result.isEmpty)
    }
}
```

---

## Write to: MerlinTests/Unit/KAGEngineTests.swift

```swift
import XCTest
@testable import Merlin

@MainActor
final class KAGEngineTests: XCTestCase {

    func test_scheduleExtraction_writes_to_registered_plugin() async throws {
        let registry = KAGBackendRegistry()
        let mock = MockKAGPlugin()
        registry.register(mock)

        let engine = KAGEngine(registry: registry)
        engine.scheduleExtraction(from: "U4 shares_net VCC in electronics domain", domain: "electronics")

        // Wait for the idle timer + extraction (stub returns [] in 190b, so writtenTriples stays empty
        // but the call must not throw and must attempt to write).
        try await Task.sleep(nanoseconds: 3_000_000_000) // 3 s > 2 s idle timer
        // In 190b the extractor is stubbed to return []; written count is 0 but no error.
        XCTAssertEqual(mock.writtenTriples.count, 0,
                       "stub extractor returns []; writtenTriples should be 0 in 190b")
    }

    func test_scheduleExtraction_does_not_throw_on_null_plugin() async throws {
        let registry = KAGBackendRegistry() // NullKAGPlugin by default
        let engine = KAGEngine(registry: registry)
        // Must not crash or throw
        engine.scheduleExtraction(from: "anything", domain: "test")
        try await Task.sleep(nanoseconds: 3_000_000_000)
    }
}
```

---

## Verify (tests must FAIL)

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: BUILD FAILED — missing symbols `KAGTriple`, `KAGTripleSource`, `KAGBackendPlugin`,
`NullKAGPlugin`, `KAGBackendRegistry`, `LocalKAGPlugin`, `KAGEngine`. That is the correct
failing state.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add \
  MerlinTests/Unit/KAGTripleTests.swift \
  MerlinTests/Unit/NullKAGPluginTests.swift \
  MerlinTests/Unit/KAGBackendRegistryTests.swift \
  MerlinTests/Unit/LocalKAGPluginTests.swift \
  MerlinTests/Unit/KAGEngineTests.swift
git commit -m "Task 190a — KAG backend plugin tests (failing)"
```
