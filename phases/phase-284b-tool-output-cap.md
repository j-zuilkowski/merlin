# Phase 284b — Tool Output Cap

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 284a complete: failing tests for `ToolOutput.clamp`.

After this phase no single tool result can overrun the context: `run_shell` and
`read_file` output is bounded before it reaches the model, the way every production
agent harness bounds it.

---

## Edit

### 1. New file — `Merlin/Tools/ToolOutput.swift`

```swift
import Foundation

/// Bounds the size of a tool result before it enters the conversation context.
/// A single `git diff` / `cargo test` / large file read must never overrun the
/// provider's input window.
enum ToolOutput {

    /// Maximum characters of a tool result allowed into the model context.
    static let maxChars = 30_000

    /// Returns `text` unchanged when within `maxChars`; otherwise returns the head
    /// plus the tail of `text` with an elision marker between them. Head and tail are
    /// both kept — a `cargo test` summary lives at the end, a `git diff` header at the
    /// start.
    static func clamp(_ text: String, maxChars: Int = maxChars) -> String {
        guard text.count > maxChars else { return text }
        let headChars = maxChars * 2 / 3
        let tailChars = maxChars - headChars
        let head = String(text.prefix(headChars))
        let tail = String(text.suffix(tailChars))
        let elided = text.count - head.count - tail.count
        return head
            + "\n\n[… \(elided) characters elided — tool output truncated to "
            + "\(maxChars) chars. Re-run with a narrower command or read a specific "
            + "range to see more. …]\n\n"
            + tail
    }
}
```

### 2. Apply the cap at the agent-facing tool-result boundary

Find the **`run_shell`** and **`read_file`** built-in tool handlers — the code in the
tool registry / built-in tool implementations that turns a `ShellResult` /
`FileSystemTools.readFile` return value into the result string handed back to the model.
Wrap the final result string in `ToolOutput.clamp(...)`:

- `run_shell`: clamp the combined stdout/stderr string the handler produces.
- `read_file`: clamp the file content the handler returns.

**Do NOT** put the cap inside `ShellTool.run()` or `FileSystemTools.readFile()` — those
are also called by `XcodeTools` (build/test) and `CriticEngine`, which parse the *full*
output. The cap belongs only on the path that feeds the model. The live terminal UI
uses `ShellTool.stream()` and is unaffected — it still shows everything.

If other built-in tool handlers can return unbounded text (e.g. `search_files`,
`list_directory` already caps by entry count — leave it), apply `ToolOutput.clamp` to
their result strings too as a uniform safety net.

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

Expected: **BUILD SUCCEEDED**, all phase 284a tests pass, no prior phase regresses.

**Manual check:** in a large repo, have the agent run `git diff` on a big change or
`read_file` on a large file. The tool result in the conversation must be truncated with
the elision marker; the live terminal pane must still show the full output.

## Commit

```bash
git add phases/phase-284b-tool-output-cap.md \
    Merlin/Tools/ToolOutput.swift \
    Merlin.xcodeproj/project.pbxproj \
    <the run_shell / read_file handler file(s)>
git commit -m "Phase 284b — Cap run_shell and read_file output before it enters context"
```

(Run `xcodegen generate` for the new `ToolOutput.swift`; commit the regenerated
`project.pbxproj`.)

## Fixes

`run_shell` and `read_file` results are bounded to `ToolOutput.maxChars` before entering
the context, so a single large tool output can no longer overrun the provider input
window. This is the upstream fix for the context-overflow 400s the v2.1 budget layer
was left to mitigate downstream.

## Follow-up (not in this phase)

`read_file` is whole-file only. Adding `offset` / `limit` parameters (like a standard
Read tool) would let the agent page through a large file instead of receiving a clamped
slice — a worthwhile enhancement, separate from this safety cap.
