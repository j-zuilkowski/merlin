# Phase diag-10a — Toolbar Actions Tests

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Working dir: ~/Documents/localProject/merlin

New surface introduced in phase diag-10b:
  - `ToolbarAction` — `Identifiable & Codable & Sendable` struct; `id`, `label`,
    `command`, `shortcut?`; `run()` executes command via `/bin/sh -c`
  - `ToolbarActionError.nonZeroExit(Int, String)` — error thrown on non-zero exit
  - `ToolbarActionStore` — `actor`; `add()`, `remove(id:)`, `all()`, `update()`,
    `load(from:)`, `save(to:)` — JSON persistence to a path string

TDD coverage:
  File — ToolbarActionTests: add/remove/all ordering, update, Codable round-trip,
    load/save round-trip, duplicate add is ignored

---

## Write to: MerlinTests/Unit/ToolbarActionTests.swift

```swift
import XCTest
@testable import Merlin

final class ToolbarActionTests: XCTestCase {

    func testToolbarActionCodableRoundTrip() throws {
        let action = ToolbarAction(
            id: UUID(),
            label: "Run tests",
            command: "swift test",
            shortcut: "⌘T"
        )
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(ToolbarAction.self, from: data)
        XCTAssertEqual(decoded.id, action.id)
        XCTAssertEqual(decoded.label, action.label)
        XCTAssertEqual(decoded.command, action.command)
        XCTAssertEqual(decoded.shortcut, action.shortcut)
    }

    func testStoreAddAndAll() async {
        let store = ToolbarActionStore()
        let a = ToolbarAction(id: UUID(), label: "A", command: "echo a", shortcut: nil)
        let b = ToolbarAction(id: UUID(), label: "B", command: "echo b", shortcut: nil)
        await store.add(a)
        await store.add(b)
        let all = await store.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all[0].label, "A")
        XCTAssertEqual(all[1].label, "B")
    }

    func testStoreDuplicateAddIsIgnored() async {
        let store = ToolbarActionStore()
        let a = ToolbarAction(id: UUID(), label: "A", command: "echo a", shortcut: nil)
        await store.add(a)
        await store.add(a)
        let all = await store.all()
        XCTAssertEqual(all.count, 1)
    }

    func testStoreRemove() async {
        let store = ToolbarActionStore()
        let a = ToolbarAction(id: UUID(), label: "A", command: "echo a", shortcut: nil)
        await store.add(a)
        await store.remove(id: a.id)
        let all = await store.all()
        XCTAssertTrue(all.isEmpty)
    }

    func testStoreUpdate() async {
        let store = ToolbarActionStore()
        let a = ToolbarAction(id: UUID(), label: "Original", command: "echo a", shortcut: nil)
        await store.add(a)
        let updated = ToolbarAction(id: a.id, label: "Updated", command: "echo b", shortcut: "⌘U")
        await store.update(updated)
        let all = await store.all()
        XCTAssertEqual(all.first?.label, "Updated")
        XCTAssertEqual(all.first?.shortcut, "⌘U")
    }

    func testStoreSaveAndLoad() async throws {
        let path = "/tmp/toolbar-actions-test-\(UUID().uuidString).json"
        defer { try? FileManager.default.removeItem(atPath: path) }

        let store = ToolbarActionStore()
        let a = ToolbarAction(id: UUID(), label: "Build", command: "xcodebuild", shortcut: "⌘B")
        await store.add(a)
        await store.save(to: path)

        let store2 = ToolbarActionStore()
        await store2.load(from: path)
        let loaded = await store2.all()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.label, "Build")
        XCTAssertEqual(loaded.first?.command, "xcodebuild")
    }
}
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD SUCCEEDED (ToolbarAction + ToolbarActionStore already exist).

## Commit
```bash
cd ~/Documents/localProject/merlin
git add phases/phase-diag-10a-toolbar-actions-tests.md \
        MerlinTests/Unit/ToolbarActionTests.swift
git commit -m "Phase diag-10a — ToolbarActionTests"
```
