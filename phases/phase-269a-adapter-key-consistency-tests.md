# Phase 269a — Adapter Key Consistency Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 268b complete: scanner accuracy fixes landed.

**Bug (High — adapter lookup mismatch).** `AdapterRegistry.loadFromDirectory` registers
each parsed adapter under `adapter.language` — `"swift"`, `"rust"`. But `ProjectConfig`
(from `.merlin/project.toml`) identifies the project's adapter by **adapter-key** — the
TOML filename stem: `"swift-xcode"`, `"rust-cargo"`. A call to
`registry.adapter(for: config.adapter)` therefore throws `AdapterError.notFound` for
every real project, because no adapter is registered under `"swift-xcode"`.

New surface introduced in phase 269b:
  - `AdapterRegistry.loadFromDirectory` registers each adapter under the TOML filename
    stem (`file.deletingPathExtension().lastPathComponent`) — the adapter-key — instead
    of `adapter.language`. `register(_:for:)` for explicit keys is retained.

TDD coverage:
  File 1 — `AdapterKeyConsistencyTests.swift`: write the seed adapters to a temp dir via
    `AdapterRegistry.installSeedAdapters(into:)`, `loadFromDirectory` it, then assert
    `adapter(for: "swift-xcode")` and `adapter(for: "rust-cargo")` both succeed and that
    the returned adapters' `language` fields are `"swift"` / `"rust"`.

---

## Write to: MerlinTests/Unit/AdapterKeyConsistencyTests.swift

```swift
import XCTest
@testable import Merlin

final class AdapterKeyConsistencyTests: XCTestCase {

    func testSeedAdaptersAreKeyedByAdapterKey() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }

        try await AdapterRegistry.installSeedAdapters(into: dir.path)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)

        // The seed files are swift-xcode.toml and rust-cargo.toml. ProjectConfig.adapter
        // identifies the adapter by that filename stem, so lookup must succeed by key.
        let swift = try await registry.adapter(for: "swift-xcode")
        XCTAssertEqual(swift.language, "swift",
            "Adapter registered under key 'swift-xcode' describes the swift language")

        let rust = try await registry.adapter(for: "rust-cargo")
        XCTAssertEqual(rust.language, "rust",
            "Adapter registered under key 'rust-cargo' describes the rust language")
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**, but `AdapterKeyConsistencyTests` FAILS at runtime —
`loadFromDirectory` currently registers under `adapter.language` (`"swift"`, `"rust"`),
so `adapter(for: "swift-xcode")` throws `notFound`. Phase 269b makes it pass.

## Commit

```bash
git add phases/phase-269a-adapter-key-consistency-tests.md \
    MerlinTests/Unit/AdapterKeyConsistencyTests.swift
git commit -m "Phase 269a — AdapterKeyConsistencyTests (failing)"
```
