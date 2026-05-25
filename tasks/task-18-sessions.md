# Phase 18 — Session + SessionStore

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 02b complete: Message type exists.

---

## Write to: Merlin/Sessions/Session.swift

```swift
import Foundation

struct Session: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String           // auto-generated from first user message (first 50 chars)
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var providerDefault: String = "deepseek-v4-pro"
    var messages: [Message]
    var authPatternsUsed: [String] = []

    // Returns first 50 chars of first user message content, or "New Session"
    static func generateTitle(from messages: [Message]) -> String
}
```

---

## Write to: Merlin/Sessions/SessionStore.swift

```swift
import Foundation

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [Session] = []
    @Published var activeSessionID: UUID?

    let storeDirectory: URL  // instance property, not static

    // Production init — uses ~/Library/Application Support/Merlin/sessions/
    convenience init()

    // Testable init — accepts any directory
    init(storeDirectory: URL)  // creates directory if needed, loads existing sessions

    func create() -> Session
    func save(_ session: Session) throws   // writes to storeDirectory/<id>.json
    func delete(_ id: UUID) throws
    func load(id: UUID) throws -> Session
    var activeSession: Session? { get }
}
```

---

## Write to: MerlinTests/Unit/SessionSerializationTests.swift

```swift
import XCTest
@testable import Merlin

final class SessionSerializationTests: XCTestCase {
    var tmp: URL!

    override func setUp() {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: tmp) }

    func testSessionRoundTrip() throws {
        let session = Session(title: "Test",
                              messages: [Message(role: .user, content: .text("hi"), timestamp: Date())])
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(Session.self, from: data)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.messages.count, 1)
    }

    func testTitleGeneration() {
        let msgs = [Message(role: .user, content: .text("How do I fix this crash in AppDelegate?"), timestamp: Date())]
        let title = Session.generateTitle(from: msgs)
        XCTAssertTrue(title.contains("How do I fix"))
    }

    func testTitleDefaultsForEmpty() {
        XCTAssertEqual(Session.generateTitle(from: []), "New Session")
    }

    func testStoreSavesAndLoads() async throws {
        let store = await SessionStore(storeDirectory: tmp)
        var s = store.create()
        s.messages.append(Message(role: .user, content: .text("hello"), timestamp: Date()))
        try store.save(s)
        let loaded = try store.load(id: s.id)
        XCTAssertEqual(loaded.messages.count, 1)
    }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test-without-building -destination 'platform=macOS' -only-testing:MerlinTests/SessionSerializationTests 2>&1 | grep -E 'passed|failed|error:|BUILD'
```

Expected: `Test Suite 'SessionSerializationTests' passed` with 4 tests.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Sessions/Session.swift Merlin/Sessions/SessionStore.swift \
    MerlinTests/Unit/SessionSerializationTests.swift
git commit -m "Phase 18 — Session + SessionStore + tests (4 tests passing)"
```
