# Phase 07b — FileSystemTools + ShellTool Implementation

Context: HANDOFF.md. Make phase-07a tests pass.

## Write to: Merlin/Tools/FileSystemTools.swift

```swift
import Foundation

enum FileSystemTools {
    // Returns file contents prefixed with "N\t" line numbers
    static func readFile(path: String) async throws -> String

    // Creates intermediate directories if needed
    static func writeFile(path: String, content: String) async throws

    static func createFile(path: String) async throws

    static func deleteFile(path: String) async throws

    // recursive: false = top-level only
    static func listDirectory(path: String, recursive: Bool) async throws -> String

    static func moveFile(src: String, dst: String) async throws

    // pattern: glob (e.g. "*.swift"), contentPattern: optional grep string
    // Returns matching file paths, one per line
    static func searchFiles(path: String, pattern: String, contentPattern: String?) async throws -> String
}
```

## Write to: Merlin/Tools/ShellTool.swift

```swift
import Foundation

struct ShellResult: Sendable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

struct ShellOutputLine: Sendable {
    enum Source: Sendable { case stdout, stderr }
    var text: String
    var source: Source
}

enum ShellTool {
    // Streaming variant — yields lines as the process produces them.
    // Used by ToolRouter to populate AppState.toolLogLines in real time.
    static func stream(command: String, cwd: String?,
                       timeoutSeconds: Int = 120) -> AsyncThrowingStream<ShellOutputLine, Error>

    // Collecting variant — awaits completion, returns full result.
    // Implemented by consuming stream().
    static func run(command: String, cwd: String?,
                    timeoutSeconds: Int = 120) async throws -> ShellResult
}
```

Implement `stream` using `Foundation.Process` with two `Pipe`s (stdout + stderr).
Launch `/bin/zsh -c <command>`.

**Process termination (critical — do not block the thread):**
`process.waitUntilExit()` is synchronous and blocks the calling thread. Instead, use
a `CheckedContinuation` with the process termination handler:

```swift
let exitCode: Int32 = try await withCheckedThrowingContinuation { cont in
    process.terminationHandler = { p in cont.resume(returning: p.terminationStatus) }
    do { try process.run() } catch { cont.resume(throwing: error) }
}
```

Read stdout and stderr via `TaskGroup`, one child task per pipe reading
`pipe.fileHandleForReading.bytes.lines`. Yield each line as a `ShellOutputLine`
into the `AsyncThrowingStream` continuation. Start the process, then await both
pipe-reader tasks in the group, then await the exit-code continuation.

Cancel the process on timeout: wrap in `Task` with `.timeLimit` or use
`Task.sleep` + `process.terminate()` in a racing task.

`run` collects all lines from `stream`, joins stdout and stderr separately, and
returns `ShellResult` with the resolved `exitCode`.

## Acceptance
- [ ] `swift test --filter FileSystemToolTests` — all 5 pass
- [ ] `swift test --filter ShellToolTests` — all 4 pass
