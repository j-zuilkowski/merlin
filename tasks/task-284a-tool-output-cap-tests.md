# Phase 284a — Tool Output Cap Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
v2.2.3 released.

**The bug.** Merlin's tools return unbounded output. `ShellTool.run()` joins every line
of `stdout`/`stderr` with no cap (`ShellTool.swift:95-104`); `FileSystemTools.readFile()`
returns the whole file (`FileSystemTools.swift:4-5`). A single `git diff`,
`cargo test --workspace`, or `read_file` on a large file dumps its entire output into
the conversation context. On a large repo this overruns the provider's input window and
the request is rejected with HTTP 400 — even on a light task. Every production agent
harness caps tool output at the source; Merlin does not.

New surface introduced in phase 284b:
  - `ToolOutput` enum in `Merlin/Tools/ToolOutput.swift`:
    ```swift
    enum ToolOutput {
        static let maxChars: Int           // default cap for a tool result
        static func clamp(_ text: String, maxChars: Int = maxChars) -> String
    }
    ```
    `clamp` returns `text` unchanged when within `maxChars`; otherwise returns the head
    plus the tail of `text` with an elision marker in between, so the result length is
    bounded. Head **and** tail are both kept — a `cargo test` summary is at the end, a
    `git diff` header at the start.
  - 284b applies `ToolOutput.clamp` in the `run_shell` and `read_file` tool handlers
    (the agent-facing result boundary).

TDD coverage:
  File 1 — `MerlinTests/Unit/ToolOutputClampTests.swift`: `clamp` is identity below the
    cap; above the cap the result is length-bounded, carries the elision marker, and
    preserves both the original head and the original tail.

---

## Write to: MerlinTests/Unit/ToolOutputClampTests.swift

```swift
import XCTest
@testable import Merlin

final class ToolOutputClampTests: XCTestCase {

    func testShortOutputIsUnchanged() {
        let text = "the quick brown fox"
        XCTAssertEqual(ToolOutput.clamp(text), text)
    }

    func testEmptyOutputIsUnchanged() {
        XCTAssertEqual(ToolOutput.clamp(""), "")
    }

    func testOutputExactlyAtCapIsUnchanged() {
        let text = String(repeating: "x", count: 200)
        XCTAssertEqual(ToolOutput.clamp(text, maxChars: 200), text)
    }

    func testOversizedOutputIsClampedAndBounded() {
        let text = String(repeating: "x", count: 5_000)
        let clamped = ToolOutput.clamp(text, maxChars: 1_000)
        XCTAssertLessThan(clamped.count, text.count,
                          "oversized output must be shortened")
        // Allow headroom for the elision marker itself.
        XCTAssertLessThan(clamped.count, 1_500,
                          "clamped output must be bounded near maxChars")
    }

    func testClampedOutputCarriesElisionMarker() {
        let text = String(repeating: "x", count: 5_000)
        let clamped = ToolOutput.clamp(text, maxChars: 1_000)
        XCTAssertTrue(clamped.lowercased().contains("elided"),
                      "clamped output must state that content was elided")
    }

    func testClampedOutputKeepsHeadAndTail() {
        let head = String(repeating: "H", count: 100)
        let middle = String(repeating: "m", count: 5_000)
        let tail = String(repeating: "T", count: 100)
        let text = head + middle + tail
        let clamped = ToolOutput.clamp(text, maxChars: 1_000)
        XCTAssertTrue(clamped.hasPrefix(head),
                      "the original head must be preserved")
        XCTAssertTrue(clamped.hasSuffix(tail),
                      "the original tail must be preserved")
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
```

Expected: **BUILD FAILED** — errors naming the missing `ToolOutput` type and its
`clamp` / `maxChars` members.

## Commit

```bash
git add tasks/task-284a-tool-output-cap-tests.md \
    MerlinTests/Unit/ToolOutputClampTests.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Phase 284a — ToolOutputClampTests (failing)"
```

(Run `xcodegen generate` so the new test file is registered before committing the
regenerated `project.pbxproj`.)
