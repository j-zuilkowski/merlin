# Merlin — Architecture Document

## Overview

Merlin is a personal, non-distributed agentic development assistant for macOS. It connects to DeepSeek V4 (remote) and LM Studio (local) as LLM providers, exposes a rich tool registry covering file system, shell, Xcode, and GUI automation, and presents a SwiftUI chat interface. It is a functional replacement for OpenAI Codex App, operating against DeepSeek V4 rather than GPT/o-series models.

**Target hardware:** M4 Mac Studio, 128GB unified memory
**Language:** Swift (SwiftUI + Swift Concurrency)
**Distribution:** Direct, non-sandboxed `.app` bundle — personal use only

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          SwiftUI Shell                              │
│   ChatView │ ToolLogView │ ScreenPreviewView │ AuthPopupView        │
├─────────────────────────────────────────────────────────────────────┤
│                         Agentic Engine                              │
│                                                                     │
│  ┌─────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │  ContextManager  │  │   ToolRouter     │  │   AuthGate        │  │
│  │  (1M window +   │  │  (discovery +    │  │  (sandbox +       │  │
│  │   compaction)   │  │   dispatch)      │  │   memory)         │  │
│  └─────────────────┘  └──────────────────┘  └───────────────────┘  │
├─────────────────────────┬───────────────────────────────────────────┤
│     Provider Layer      │            Tool Registry                  │
│                         │                                           │
│  ┌─────────────────┐    │  FileSystemTools    XcodeTools            │
│  │ deepseek-v4-pro │    │  ShellTool          SimulatorTools        │
│  │ deepseek-v4-    │    │  AppLaunchTool      ToolDiscovery         │
│  │ flash           │    │  AXInspectorTool    ScreenCaptureTool     │
│  └─────────────────┘    │  CGEventTool        VisionQueryTool       │
│  ┌─────────────────┐    │                                           │
│  │  LM Studio      │    │                                           │
│  │  (localhost:    │    │                                           │
│  │   1234)         │    │                                           │
│  └─────────────────┘    │                                           │
└─────────────────────────┴───────────────────────────────────────────┘
```

---

## Provider Layer

### Design Decision: OpenAI Function Calling Format

All tool definitions use the OpenAI function calling wire format throughout. Both DeepSeek V4 and LM Studio speak this format natively. A single `ToolDefinition` schema works across all providers with no translation layer.

### Protocol

```swift
protocol LLMProvider {
    var id: String { get }
    var baseURL: URL { get }
    var apiKey: String? { get }
    func complete(request: CompletionRequest) async throws -> AsyncThrowingStream<CompletionChunk, Error>
}
```

### Providers

**DeepSeek V4 Pro** (`deepseek-v4-pro`)
- Endpoint: `https://api.deepseek.com/v1/chat/completions`
- Context: 1,000,000 tokens / 384K max output
- Use: Heavy reasoning, architecture decisions, long-context analysis, debugging
- Thinking mode: auto-enabled (see Thinking Mode section)
- Auth: API key from macOS Keychain

**DeepSeek V4 Flash** (`deepseek-v4-flash`)
- Endpoint: `https://api.deepseek.com/v1/chat/completions`
- Context: 1,000,000 tokens / 384K max output
- Use: High-frequency tool loops, file read/write, shell execution, mechanical tasks
- Thinking mode: off by default
- Auth: API key from macOS Keychain

**LM Studio** (local vision model)
- Endpoint: `http://localhost:1234/v1/chat/completions`
- Model: `Qwen2.5-VL-72B-Instruct-Q4_K_M`
- Use: GUI screenshot analysis exclusively — never used for text reasoning tasks
- Auth: None

### Thinking Mode Auto-Detection

Thinking mode is enabled on `deepseek-v4-pro` requests when the user message or accumulated reasoning context contains signal words: `debug`, `why`, `architecture`, `design`, `explain`, `error`, `failing`, `unexpected`, `broken`, `investigate`. Disabled for: `read`, `write`, `run`, `list`, `build`, `open`, `create`, `delete`. A manual toggle in the UI overrides auto-detection.

```json
// Thinking enabled
{ "thinking": { "type": "enabled" }, "reasoning_effort": "high" }

// Thinking disabled
{ "thinking": { "type": "disabled" } }
```

### Runtime Provider Selection

```
User message arrives
│
├── GUI screenshot task?          → LM Studio (Qwen2.5-VL-72B)
├── Mechanical / tool loop?       → deepseek-v4-flash
└── Reasoning / analysis / debug? → deepseek-v4-pro
```

The engine selects the provider per-turn. The UI shows a small provider indicator so the user can see which model handled each response.

---

## Agentic Engine

### Loop Structure

```
1.  Receive user message
2.  Append to context
3.  Select provider (see Runtime Provider Selection)
4.  Stream completion — accumulate text and tool_calls
5.  If no tool_calls in response → stream final text to UI, end turn
6.  For each tool_call:
    a. Pass through AuthGate (approve / deny / remember)
    b. If denied → append denial result to context, continue loop
    c. If approved → execute tool, stream output to ToolLogView
    d. Append tool result to context
7.  Go to step 3 (loop continues until a turn produces no tool_calls)
```

Parallel tool calls (where declared independent by the model) are dispatched concurrently via Swift structured concurrency (`async let` / `TaskGroup`).

### Error Policy

On tool execution failure:
1. **First failure** — retry once silently after 1 second
2. **Second failure** — pause loop, surface to user: show tool name, arguments, error message, and options: Retry / Skip / Abort
3. Auth patterns are never written on failed calls

### Context Manager

- Maintains the full message array including tool call results
- Tracks running token estimate (character count ÷ 3.5 as a fast approximation)
- At **800,000 tokens**: fires compaction
  - Summarizes tool call result messages older than 20 turns into a compact digest
  - Preserves all user and assistant messages verbatim
  - Appends a `[context compacted]` system note to the conversation
- The 1M context window makes compaction rare in normal sessions — it is a safety net, not a routine operation

---

## Auth Gate & Sandbox

Every tool call passes through `AuthGate` before execution. This is the sole enforcement point — no tool executes without clearing it.

### Decision Flow

```
AuthGate.check(toolCall)
│
├── Matches a remembered ALLOW pattern? → execute silently
├── Matches a remembered DENY pattern?  → block silently, return error result
└── No match → show AuthPopupView
    ├── Allow Once     → execute, do not persist
    ├── Allow Always for <pattern> → execute, persist allow rule
    ├── Deny Once      → block, do not persist
    └── Deny Always for <pattern>  → block, persist deny rule
```

### Pattern Matching

Patterns are stored at a glob level, not per exact call:

| Tool | Example Pattern |
|---|---|
| `read_file` | `~/Documents/localProject/**` |
| `run_shell` | `xcodebuild *` |
| `app_launch` | `com.apple.Xcode` |
| `write_file` | `~/Documents/localProject/merlin/**` |

### Auth Memory Storage

Persisted to `~/Library/Application Support/Merlin/auth.json`. Structure:

```json
{
  "allowPatterns": [
    { "tool": "read_file", "pattern": "~/Documents/localProject/**", "addedAt": "..." },
    { "tool": "run_shell", "pattern": "xcodebuild *", "addedAt": "..." }
  ],
  "denyPatterns": [
    { "tool": "run_shell", "pattern": "rm -rf *", "addedAt": "..." }
  ]
}
```

### Auth Popup UI

The popup displays:
- Tool name and icon
- Full arguments (formatted, not truncated)
- Which reasoning step triggered the call
- The glob pattern that would be remembered if "Allow Always" is chosen
- Keyboard shortcuts: `⌘↩` Allow Once, `⌥⌘↩` Allow Always, `⎋` Deny

---

## Tool Registry

All tools are defined as OpenAI function call schemas and registered at app launch. The agent sees the full list in its system prompt.

### File System Tools

| Tool | Description |
|---|---|
| `read_file(path)` | Returns file contents with line numbers |
| `write_file(path, content)` | Writes or overwrites a file |
| `create_file(path)` | Creates an empty file |
| `delete_file(path)` | Deletes a file (requires auth) |
| `list_directory(path, recursive?)` | Returns directory tree |
| `move_file(src, dst)` | Moves or renames |
| `search_files(pattern, path, content_pattern?)` | Glob + optional grep |

### Shell Tool

`run_shell(command, cwd?, timeout_seconds?)`

- Executes via `Foundation.Process`
- Captures stdout and stderr separately
- Streams output lines to ToolLogView in real time
- Default timeout: 120 seconds; Xcode builds: 600 seconds
- Working directory defaults to the active project path

### App Launch & Control

| Tool | Description |
|---|---|
| `app_launch(bundle_id, arguments?)` | Launch via NSWorkspace |
| `app_list_running()` | Returns running app bundle IDs and PIDs |
| `app_quit(bundle_id)` | Graceful quit |
| `app_focus(bundle_id)` | Bring app to foreground |

### Tool Discovery

`tool_discover()` — scans `$PATH` at call time and returns a list of installed CLI tools with their `--help` summaries where available. Any discovered tool can be invoked via `run_shell`. All shell invocations go through AuthGate regardless of discovery status. New tools discovered at runtime require explicit Allow on first execution — they never run silently.

### Xcode Tools (Deep Integration)

| Tool | Description |
|---|---|
| `xcode_build(scheme, configuration, destination?)` | Runs `xcodebuild`, streams output |
| `xcode_test(scheme, test_id?)` | Runs test suite or single test |
| `xcode_clean()` | Cleans build folder |
| `xcode_derived_data_clean()` | Nukes DerivedData |
| `xcode_open_file(path, line)` | Opens file at line in Xcode via AppleScript |
| `xcode_xcresult_parse(path)` | Extracts failures, warnings, coverage from `.xcresult` |
| `xcode_simulator_list()` | Returns available simulators with UDID, runtime, state |
| `xcode_simulator_boot(udid)` | Boots a simulator |
| `xcode_simulator_screenshot(udid)` | Captures simulator screen |
| `xcode_simulator_install(udid, app_path)` | Installs `.app` on simulator |
| `xcode_spm_resolve()` | Runs `swift package resolve` |
| `xcode_spm_list()` | Lists resolved SPM dependencies |

Build output is parsed for errors and warnings and structured into a typed result before being appended to context, rather than dumping raw `xcodebuild` log text.

---

## GUI Automation

Three strategies operate in concert. The agent selects observation strategy per app based on AX availability; CGEvent is always the execution layer.

### Strategy A — Accessibility Tree (AXUIElement)

Used when the target app exposes a usable accessibility hierarchy (native macOS apps, Xcode, Terminal, most AppKit/SwiftUI apps).

| Tool | Description |
|---|---|
| `ui_inspect(bundle_id)` | Returns full AX element tree as structured JSON |
| `ui_find_element(bundle_id, role?, label?, value?)` | Locates a specific element |
| `ui_get_element_value(element_id)` | Reads current value of a field or control |

Requires **Accessibility permission** granted in System Settings → Privacy & Security → Accessibility.

### Strategy B — Screenshot + Vision (LM Studio)

Used when AX tree is shallow or absent (Electron apps, Unity, web views, custom-drawn UIs).

| Tool | Description |
|---|---|
| `ui_screenshot(bundle_id?, region?)` | Captures window or screen region via ScreenCaptureKit |
| `vision_query(image_id, prompt)` | Sends captured frame to Qwen2.5-VL-72B, returns response |

Screenshot parameters:
- Capture at **logical resolution** (not 2x retina) — 4x fewer pixels, no meaningful UI detail loss
- Encode as **JPEG quality 85** before base64
- Crop to active window bounds when possible
- Target under 1MB before encoding

Requires **Screen Recording permission** granted in System Settings → Privacy & Security → Screen Recording.

The vision model is called with `temperature: 0.1` and a 256-token max for coordinate/action responses. Prompts request structured JSON output: `{"x": int, "y": int, "action": string, "confidence": float}`.

### Strategy C — Input Simulation (CGEvent)

Execution layer for both A and B. Always used to perform actions, never for observation.

| Tool | Description |
|---|---|
| `ui_click(x, y, button?)` | Mouse click at screen coordinates |
| `ui_double_click(x, y)` | Double click |
| `ui_right_click(x, y)` | Context menu trigger |
| `ui_drag(from_x, from_y, to_x, to_y)` | Click-drag |
| `ui_type(text)` | Keyboard input |
| `ui_key(key_combo)` | Modifier + key (e.g. `cmd+s`) |
| `ui_scroll(x, y, delta_x, delta_y)` | Scroll at coordinates |

### Runtime Strategy Selection

```swift
func selectGUIStrategy(for bundleID: String) async -> GUIObservationStrategy {
    let tree = await AXInspector.probe(bundleID)
    return tree.elementCount > 10 && tree.hasLabels ? .accessibilityTree : .visionModel
}
```

The probe result is cached per-app for the session duration unless the app is relaunched.

---

## Session Persistence

Sessions are saved to `~/Library/Application Support/Merlin/sessions/` as JSON files.

### Session File Structure

```json
{
  "id": "uuid",
  "title": "auto-generated from first user message",
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601",
  "providerDefault": "deepseek-v4-pro",
  "messages": [
    {
      "role": "user | assistant | tool",
      "content": "...",
      "toolCalls": [...],
      "toolCallId": "...",
      "thinkingContent": "...",
      "timestamp": "ISO8601"
    }
  ],
  "authPatternsUsed": ["pattern1", "pattern2"]
}
```

Full message history is preserved including tool call results — no summarization at save time. The 1M context window means sessions can be restored and continued without re-summarizing. Sessions are written incrementally after each turn (not only on close) to survive crashes.

---

## SwiftUI Interface

### Views

**ChatView** — primary conversation thread. Messages rendered with markdown. Tool calls shown inline as collapsible cards displaying tool name, arguments, and result summary. Thinking content shown in a dimmed expandable block when present.

**ToolLogView** — right panel. Live stdout/stderr stream from running tool calls. Color-coded by source (stdout: default, stderr: orange, system: gray). Cleared between turns or pinned by user choice.

**ScreenPreviewView** — bottom panel (collapsible). Displays the last screenshot captured by `ui_screenshot`. Shows capture timestamp and source app. On-demand only — no live stream.

**AuthPopupView** — modal sheet. Appears over the main window. Non-dismissable via background click. Shows full tool call context, pattern preview, and keyboard shortcuts.

**ProviderHUD** — small persistent indicator in toolbar showing which provider handled the last response and whether thinking mode was active.

### App Entitlements Required

```xml
<key>com.apple.security.app-sandbox</key>
<false/>  <!-- Non-sandboxed for full file system and process access -->

<key>com.apple.security.network.client</key>
<true/>   <!-- DeepSeek API calls -->
```

System permissions required at first launch (requested on demand, not all at once):
- **Accessibility** — for AX tree inspection and CGEvent input simulation
- **Screen Recording** — for ScreenCaptureKit window capture

Both are requested the first time the relevant tool is invoked, with a clear explanation shown to the user before the system dialog appears.

---

## API Key Management

DeepSeek API key stored in macOS Keychain:

```
Service:  com.merlin.deepseek
Account:  api-key
```

Read at app launch via `SecItemCopyMatching`. If absent, a first-launch setup sheet prompts for the key and writes it to Keychain. The key is never written to disk in plaintext, never included in session JSON, and never logged.

---

## Swift Project Structure

```
Merlin/
├── App/
│   ├── MerlinApp.swift
│   └── AppState.swift              — top-level ObservableObject
├── Providers/
│   ├── LLMProvider.swift           — protocol + shared types
│   ├── DeepSeekProvider.swift
│   └── LMStudioProvider.swift
├── Engine/
│   ├── AgenticEngine.swift         — main loop
│   ├── ContextManager.swift        — token tracking + compaction
│   ├── ToolRouter.swift            — dispatch + parallel execution
│   └── ThinkingModeDetector.swift  — auto signal detection
├── Auth/
│   ├── AuthGate.swift
│   ├── AuthMemory.swift            — load/save auth.json
│   └── PatternMatcher.swift
├── Tools/
│   ├── ToolDefinitions.swift       — OpenAI function schemas
│   ├── FileSystemTools.swift
│   ├── ShellTool.swift
│   ├── AppControlTools.swift
│   ├── ToolDiscovery.swift
│   ├── XcodeTools.swift
│   ├── AXInspectorTool.swift
│   ├── ScreenCaptureTool.swift
│   ├── CGEventTool.swift
│   └── VisionQueryTool.swift
├── Sessions/
│   ├── Session.swift               — Codable session model
│   └── SessionStore.swift          — load/save/list sessions
├── Keychain/
│   └── KeychainManager.swift
└── Views/
    ├── ChatView.swift
    ├── ToolLogView.swift
    ├── ScreenPreviewView.swift
    ├── AuthPopupView.swift
    └── ProviderHUD.swift
```

---

## Key Dependencies

No third-party Swift packages in the production target. Test targets use XCTest exclusively (Apple framework).

| Framework | Purpose |
|---|---|
| `SwiftUI` | UI |
| `Foundation` | Networking, Process, JSON |
| `ScreenCaptureKit` | Window and screen capture (macOS 13+) |
| `Accessibility` | AXUIElement tree inspection |
| `CoreGraphics` | CGEvent input simulation |
| `AppKit` | NSWorkspace app launch/control |
| `Security` | Keychain read/write |
| `XCTest` | All test layers (test targets only) |

HTTP calls to DeepSeek and LM Studio use `URLSession` with async/await and server-sent event (SSE) streaming parsed manually — no Alamofire or similar.

---

## Testing Strategy (TDD)

All implementation phases are preceded by a test phase. Tests are written first; implementation makes them pass.

### Test Layers

**Layer 1 — Unit (fast, always run)**
Pure logic, no I/O, mocked providers and tools. Covers: PatternMatcher, ThinkingModeDetector, ContextManager compaction, token estimation, session JSON serialization/deserialization.

**Layer 2 — Integration (fast, always run)**
Real file system, real `Foundation.Process`, real AX/ScreenCaptureKit calls, mocked LLM responses. Covers: each tool's execution correctness, xcresult parsing, AX tree probing, screenshot capture pipeline.

**Layer 3 — Live Provider (slow, manual trigger)**
Real DeepSeek API + real LM Studio. Verifies wire format, tool call round-trips, streaming, thinking mode activation. Tagged `LiveProvider` — run via separate Xcode test scheme `MerlinTests-Live`, not on every build.

**Preconditions for Layer 3:**
- `DEEPSEEK_API_KEY` set in environment
- LM Studio running on `localhost:1234` with `Qwen2.5-VL-72B-Instruct-Q4_K_M` loaded

**Layer 4 — End-to-End Visual (slow, manual trigger)**
Full agentic loop with real models + SwiftUI UI verification. Drives the `TestTargetApp` fixture via GUI automation. Tagged `EndToEnd`.

### Visual Testing Approach (XCTest only)

No third-party snapshot library. Visual correctness is verified through:

| Concern | Method | Automated |
|---|---|---|
| Widget clipped outside container | `XCUIElement.frame` within parent bounds assertion | Yes |
| Overlapping / cluttered elements | Frame intersection checks between sibling views | Yes |
| Accessibility layout violations | `XCUIApplication().performAccessibilityAudit()` | Yes |
| Rendering artifacts | `XCTAttachment(screenshot:)` captured to test report | Manual review |

### TestTargetApp

A minimal SwiftUI app bundled as a test fixture at `TestTargetApp/`. Contains a fixed, versioned set of UI elements: buttons, text fields, labels, a list, a sheet. Used exclusively by Layer 4 end-to-end tests as the GUI automation target. Deterministic layout — does not depend on Xcode or any external app being stable.

### Project Test Structure

```
Merlin/
├── MerlinTests/                    — Layer 1 + 2 (fast, default scheme)
│   ├── Unit/
│   │   ├── PatternMatcherTests.swift
│   │   ├── ThinkingModeDetectorTests.swift
│   │   ├── ContextManagerTests.swift
│   │   └── SessionSerializationTests.swift
│   └── Integration/
│       ├── FileSystemToolTests.swift
│       ├── ShellToolTests.swift
│       ├── XcodeToolTests.swift
│       ├── AXInspectorTests.swift
│       └── ScreenCaptureTests.swift
├── MerlinLiveTests/                — Layer 3 (MerlinTests-Live scheme)
│   ├── DeepSeekProviderLiveTests.swift
│   └── LMStudioProviderLiveTests.swift
├── MerlinE2ETests/                 — Layer 4 (MerlinTests-Live scheme)
│   ├── AgenticLoopE2ETests.swift
│   ├── GUIAutomationE2ETests.swift
│   └── VisualLayoutTests.swift
└── TestTargetApp/                  — GUI automation fixture app
    ├── TestTargetAppApp.swift
    └── ContentView.swift           — fixed versioned UI elements
```

---

## Decisions Summary

| Decision | Choice |
|---|---|
| Tool call wire format | OpenAI function calling |
| Error / retry policy | Retry once silently, then surface to user |
| API key storage | macOS Keychain |
| Vision model backend | GGUF Q4_K_M in LM Studio (MLX if bottleneck observed) |
| Session persistence | Yes — full JSON in ~/Library/Application Support/Merlin/sessions/ |
| Thinking mode | Auto-detect via signal words, manual override available |
| Screen preview refresh | On-demand only (no live stream) |
| Xcode integration | Deep — xcresult, simulators, DerivedData, SPM |
| Tool discovery | Dynamic PATH scan, deny-by-default, auth required on first use |
| Context compaction | Yes — fires at 800K tokens, summarizes old tool results |
| App sandbox | Non-sandboxed, direct distribution |
| GUI strategy selection | AX tree if rich (>10 elements with labels), else vision model |
| Third-party dependencies | None — Apple frameworks only (production + test) |
| TDD | Yes — test phase precedes every implementation phase |
| Snapshot testing library | None — XCTest built-ins + manual screenshot review |
| Live test trigger | Manual — separate Xcode scheme `MerlinTests-Live` |
| GUI automation test target | Purpose-built `TestTargetApp` fixture (bundled) |
| Visual quality definition | No clipping, no overlap, accessibility audit passes, screenshots for artifact review |
