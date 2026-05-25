# Phase 48b — Hooks Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 48a complete: failing tests in place.

New files:
  - `Merlin/Hooks/HookDecision.swift`
  - `Merlin/Hooks/HookEngine.swift`
  - `Merlin/UI/Settings/HooksSettingsDetailView.swift` — replaces stub in SettingsWindowView

Hook ordering guarantee: HookEngine.runPreToolUse is called BEFORE AuthGate in AgenticEngine.
If a hook denies, the tool call is blocked immediately without showing the user an approval prompt.

---

## Write to: Merlin/Hooks/HookDecision.swift

```swift
import Foundation

enum HookDecision: Sendable {
    case allow
    case deny(reason: String)
}
```

---

## Write to: Merlin/Hooks/HookEngine.swift

```swift
import Foundation

// Executes lifecycle hook shell scripts.
// All hooks for an event run sequentially. First deny wins.
// Non-zero exit code, missing binary, or JSON parse failure = deny (fail-closed).
actor HookEngine {

    private var hooks: [HookConfig]

    init(hooks: [HookConfig] = []) {
        self.hooks = hooks
    }

    // MARK: - Configuration

    func configure(hooks: [HookConfig]) {
        self.hooks = hooks
    }

    // MARK: - Lifecycle events

    // Called before AuthGate. Returns .deny to block the tool call without user prompt.
    func runPreToolUse(toolName: String, input: [String: Any]) async -> HookDecision {
        let relevant = hooks.filter { $0.event == "PreToolUse" && $0.enabled }
        guard !relevant.isEmpty else { return .allow }

        var stdinPayload: [String: Any] = ["tool": toolName]
        if !input.isEmpty { stdinPayload["input"] = input }
        guard let stdinData = try? JSONSerialization.data(withJSONObject: stdinPayload),
              let stdinString = String(data: stdinData, encoding: .utf8) else {
            return .deny(reason: "HookEngine: failed to serialize PreToolUse payload")
        }

        for hook in relevant {
            let (stdout, exitCode) = await runScript(hook.command, stdin: stdinString)
            guard exitCode == 0, !stdout.isEmpty,
                  let data = stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let decision = json["decision"] as? String else {
                return .deny(reason: "HookEngine: hook failed or returned invalid output")
            }
            if decision == "deny" {
                let reason = json["reason"] as? String ?? "Denied by hook"
                return .deny(reason: reason)
            }
        }
        return .allow
    }

    // Called after a tool completes. Returns modified result string, or nil to pass through.
    func runPostToolUse(toolName: String, result: String) async -> String? {
        let relevant = hooks.filter { $0.event == "PostToolUse" && $0.enabled }
        guard !relevant.isEmpty else { return nil }

        let stdinPayload: [String: Any] = ["tool": toolName, "result": result]
        guard let stdinData = try? JSONSerialization.data(withJSONObject: stdinPayload),
              let stdinString = String(data: stdinData, encoding: .utf8) else { return nil }

        var current = result
        for hook in relevant {
            let (stdout, exitCode) = await runScript(hook.command, stdin: stdinString)
            guard exitCode == 0, !stdout.isEmpty else { continue }
            current = stdout
        }
        return current == result ? nil : current
    }

    // Called when user submits a prompt. Returns augmented prompt, or nil to use original.
    func runUserPromptSubmit(prompt: String) async -> String? {
        let relevant = hooks.filter { $0.event == "UserPromptSubmit" && $0.enabled }
        guard !relevant.isEmpty else { return nil }

        var current = prompt
        for hook in relevant {
            let (stdout, exitCode) = await runScript(hook.command, stdin: current)
            guard exitCode == 0, !stdout.isEmpty else { continue }
            current = stdout
        }
        return current == prompt ? nil : current
    }

    // Called when agent session is stopping. Returns false to abort stop.
    func runStop() async -> Bool {
        let relevant = hooks.filter { $0.event == "Stop" && $0.enabled }
        guard !relevant.isEmpty else { return true }

        for hook in relevant {
            let (stdout, exitCode) = await runScript(hook.command, stdin: "")
            guard exitCode == 0, !stdout.isEmpty,
                  let data = stdout.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let proceed = json["proceed"] as? Bool else {
                return true  // Stop hooks don't fail-closed — missing/bad output = proceed
            }
            if !proceed { return false }
        }
        return true
    }

    // MARK: - Script runner

    private func runScript(_ command: String, stdin: String) async -> (stdout: String, exitCode: Int) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]

            let stdinPipe  = Pipe()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardInput  = stdinPipe
            process.standardOutput = stdoutPipe
            process.standardError  = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ("", 1))
                return
            }

            if !stdin.isEmpty, let data = stdin.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
            }
            stdinPipe.fileHandleForWriting.closeFile()

            process.waitUntilExit()

            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout  = String(data: outData, encoding: .utf8)?
                              .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let code    = Int(process.terminationStatus)
            continuation.resume(returning: (stdout, code))
        }
    }
}
```

---

## Edit: Merlin/UI/Settings/SettingsWindowView.swift

Replace the stub `HooksSettingsView` body with a real implementation that lists configured hooks.
This is a simple detail; the full per-hook CRUD UI belongs in `HooksSettingsDetailView.swift`.

```swift
// Replace stub:
struct HooksSettingsView: View {
    @ObservedObject private var settings = AppSettings.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.hooks.isEmpty {
                Text("No hooks configured.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List(settings.hooks) { hook in
                    HStack {
                        Text(hook.event).bold().frame(width: 160, alignment: .leading)
                        Text(hook.command)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(hook.enabled ? .primary : .secondary)
                    }
                }
            }
            Text("Hook commands receive JSON on stdin and write JSON to stdout.\nNon-zero exit = deny (PreToolUse).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding([.horizontal, .bottom])
        }
    }
}
```

---

## Integration note

In `AgenticEngine`, before calling `AuthGate.authorize(toolName:input:)`:

```swift
let hookDecision = await hookEngine.runPreToolUse(toolName: name, input: inputDict)
if case .deny(let reason) = hookDecision {
    // Return a tool error message; do NOT show the auth prompt
    return ToolResult(error: "Blocked by hook: \(reason)")
}
// Then proceed to AuthGate...
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all HookEngineTests pass.

## Commit
```bash
git add Merlin/Hooks/HookDecision.swift \
        Merlin/Hooks/HookEngine.swift
git commit -m "Phase 48b — HookEngine (PreToolUse/PostToolUse/UserPromptSubmit/Stop lifecycle hooks)"
```
