# Phase 00 — Scaffold

## Context
Swift 5.10, macOS 14+, `async`/`await` + actors. No third-party Swift packages.
`SWIFT_STRICT_CONCURRENCY=complete`. Zero warnings, zero errors required.
Working dir: `~/Documents/localProject/merlin/plugins/merlin-kicad-mcp`

This is the first phase. It creates the Swift Package skeleton so every later phase has
a target to build into and a test target to register tests in. `CLAUDE.md` and
`phases/` (with `ROADMAP.md`) already exist — this phase adds the package and commits
everything as the initial commit.

---

## Write

### `Package.swift`

```swift
// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "merlin-kicad-mcp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "merlin-kicad-mcp",
            dependencies: ["KiCadMCPKit"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .target(
            name: "KiCadMCPKit",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "KiCadMCPKitTests",
            dependencies: ["KiCadMCPKit"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
    ]
)
```

No `dependencies:` on the package — Foundation only.

### `Sources/merlin-kicad-mcp/main.swift`

A thin entry point — a placeholder for now; phase 01 replaces the body with the real
server start. It must compile:

```swift
import KiCadMCPKit

// Phase 01 replaces this with: await MCPServer().run()
print("merlin-kicad-mcp — not yet implemented", to: &standardError)
```

(Provide a minimal `standardError` `TextOutputStream` helper in `KiCadMCPKit`, or use
`FileHandle.standardError` — phase 01 will formalise logging.)

### `Sources/KiCadMCPKit/KiCadMCPKit.swift`

A placeholder so the library target has a source file:

```swift
/// Marker for the KiCadMCPKit library. Real types arrive in phase 01+.
public enum KiCadMCPKit {
    public static let protocolName = "merlin-kicad-mcp"
}
```

### `Tests/KiCadMCPKitTests/ScaffoldTests.swift`

```swift
import XCTest
@testable import KiCadMCPKit

final class ScaffoldTests: XCTestCase {
    func testPackageBuilds() {
        XCTAssertEqual(KiCadMCPKit.protocolName, "merlin-kicad-mcp")
    }
}
```

### `.gitignore`

```
.build/
.swiftpm/
*.xcodeproj
dist/
.DS_Store
```

### `README.md`

A short README: what `merlin-kicad-mcp` is (the MCP server for Merlin's KiCad domain),
how to build (`swift build`), how to test (`swift test`), and a pointer to
`phases/ROADMAP.md` and `CLAUDE.md`.

---

## Verify

```bash
swift build 2>&1 | grep -E 'error:|warning:|Build complete' | tail -10
swift test  2>&1 | grep -E 'passed|failed|error:' | tail -10
```

Expected: **Build complete**, `ScaffoldTests.testPackageBuilds` passes.

## Commit

```bash
cd ~/Documents/localProject/merlin/plugins/merlin-kicad-mcp
# No `git init` — this package is a subdirectory of the Merlin repo and is
# tracked there. `git add` from here stages into that repo.
git add CLAUDE.md README.md .gitignore Package.swift \
    Sources/ Tests/ phases/
git commit -m "kicad-mcp Phase 00 — Swift package scaffold"
```
