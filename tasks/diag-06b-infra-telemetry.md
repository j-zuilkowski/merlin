# Phase diag-06b — Infrastructure Telemetry Implementation

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase diag-06a complete: failing tests in place.

Instrument `SessionStore`, `HookEngine`, and add `TelemetryEmitter.emitProcessMemory()`.

---

## Edit: Merlin/Telemetry/TelemetryEmitter.swift

### 1. Add `emitProcessMemory()` public method

Add the following method to `TelemetryEmitter`, after the `begin(_:data:)` method:

```swift
    /// Sample and emit current process RSS and virtual memory usage.
    /// Uses `task_info` — available on macOS without entitlements.
    public func emitProcessMemory() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let rssMB   = Double(info.resident_size)  / 1_048_576
        let vsizeMB = Double(info.virtual_size)   / 1_048_576
        emit("process.memory", data: [
            "rss_mb":   TelemetryValue.double(rssMB),
            "vsize_mb": TelemetryValue.double(vsizeMB)
        ])
    }
```

Add `import Darwin` at the top of the file if it is not already present (Foundation imports Darwin transitively on Apple platforms, so this is typically covered, but add it explicitly to be safe).

---

## Edit: Merlin/Sessions/SessionStore.swift

### 1. Instrument `save(_:)`

Find:
```swift
    func save(_ session: Session) throws {
```

Replace the body with an instrumented version:
```swift
    func save(_ session: Session) throws {
        let saveStart = Date()
        let url = storeDirectory.appendingPathComponent(session.id.uuidString + ".json")
        let data = try JSONEncoder().encode(session)
        try data.write(to: url, options: .atomic)

        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
        } else {
            sessions.append(session)
        }
        activeSessionID = session.id

        let ms = Date().timeIntervalSince(saveStart) * 1000
        TelemetryEmitter.shared.emit("session.save", durationMs: ms, data: [
            "session_id":    TelemetryValue.string(session.id.uuidString),
            "message_count": TelemetryValue.int(session.messages.count)
        ])
    }
```

---

## Edit: Merlin/Hooks/HookEngine.swift

### 1. Instrument `runPreToolUse(toolName:input:)`

Find:
```swift
    func runPreToolUse(toolName: String, input: [String: String]) async -> HookDecision {
```

At the top of the body:
```swift
        let hookStart = Date()
```

Before each `return` statement in the method, emit the event. To avoid repetition, restructure the function so there is a single exit:

```swift
    func runPreToolUse(toolName: String, input: [String: String]) async -> HookDecision {
        let hookStart = Date()
        let result = await _runPreToolUse(toolName: toolName, input: input)
        let ms = Date().timeIntervalSince(hookStart) * 1000
        let decisionStr: String
        switch result {
        case .allow: decisionStr = "allow"
        case .deny:  decisionStr = "deny"
        }
        TelemetryEmitter.shared.emit("hook.pre_tool", durationMs: ms, data: [
            "tool_name":   TelemetryValue.string(toolName),
            "decision":    TelemetryValue.string(decisionStr),
            "duration_ms": TelemetryValue.double(ms)
        ])
        return result
    }

    private func _runPreToolUse(toolName: String, input: [String: String]) async -> HookDecision {
        // (Move the existing body of runPreToolUse here verbatim)
    }
```

### 2. Instrument `runPostToolUse(toolName:result:)`

Find:
```swift
    func runPostToolUse(toolName: String, result: String) async -> String? {
```

Wrap similarly:
```swift
    func runPostToolUse(toolName: String, result: String) async -> String? {
        let hookStart = Date()
        let note = await _runPostToolUse(toolName: toolName, result: result)
        let ms = Date().timeIntervalSince(hookStart) * 1000
        TelemetryEmitter.shared.emit("hook.post_tool", durationMs: ms, data: [
            "tool_name":   TelemetryValue.string(toolName),
            "had_note":    TelemetryValue.bool(note != nil),
            "duration_ms": TelemetryValue.double(ms)
        ])
        return note
    }

    private func _runPostToolUse(toolName: String, result: String) async -> String? {
        // (Move the existing body here verbatim)
    }
```

### 3. Instrument `runUserPromptSubmit(prompt:)`

Find:
```swift
    func runUserPromptSubmit(prompt: String) async -> String? {
```

Wrap similarly:
```swift
    func runUserPromptSubmit(prompt: String) async -> String? {
        let hookStart = Date()
        let modified = await _runUserPromptSubmit(prompt: prompt)
        let ms = Date().timeIntervalSince(hookStart) * 1000
        TelemetryEmitter.shared.emit("hook.prompt_submit", durationMs: ms, data: [
            "modified":    TelemetryValue.bool(modified != nil),
            "duration_ms": TelemetryValue.double(ms)
        ])
        return modified
    }

    private func _runUserPromptSubmit(prompt: String) async -> String? {
        // (Move the existing body here verbatim)
    }
```

---

## Edit: Merlin/MCP/MCPBridge.swift

### 1. Instrument `call(server:tool:arguments:)`

Find:
```swift
    func call(server: String, tool: String, arguments: [String: Any]) async throws -> String {
```

Replace with:
```swift
    func call(server: String, tool: String, arguments: [String: Any]) async throws -> String {
        TelemetryEmitter.shared.emit("mcp.call.start", data: [
            "server": TelemetryValue.string(server),
            "tool":   TelemetryValue.string(tool)
        ])
        let callStart = Date()
        do {
            // (existing body — find the MCPServerSession and forward the call)
            let result = try await _call(server: server, tool: tool, arguments: arguments)
            let ms = Date().timeIntervalSince(callStart) * 1000
            TelemetryEmitter.shared.emit("mcp.call.complete", durationMs: ms, data: [
                "server":       TelemetryValue.string(server),
                "tool":         TelemetryValue.string(tool),
                "result_bytes": TelemetryValue.int(result.utf8.count)
            ])
            return result
        } catch {
            let ms = Date().timeIntervalSince(callStart) * 1000
            TelemetryEmitter.shared.emit("mcp.call.error", durationMs: ms, data: [
                "server":       TelemetryValue.string(server),
                "tool":         TelemetryValue.string(tool),
                "error_domain": TelemetryValue.string((error as NSError).domain),
                "error_code":   TelemetryValue.int((error as NSError).code)
            ])
            throw error
        }
    }

    private func _call(server: String, tool: String, arguments: [String: Any]) async throws -> String {
        // (Move the existing body of call(server:tool:arguments:) here verbatim)
    }
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'SessionStore|HookTelemetry|ProcessMemory|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all SessionStoreTelemetryTests, HookTelemetryTests, and ProcessMemoryTelemetryTests pass, BUILD SUCCEEDED, zero warnings.

## Commit
```bash
git add Merlin/Telemetry/TelemetryEmitter.swift \
        Merlin/Sessions/SessionStore.swift \
        Merlin/Hooks/HookEngine.swift \
        Merlin/MCP/MCPBridge.swift
git commit -m "Phase diag-06b — Infrastructure telemetry instrumentation"
```
