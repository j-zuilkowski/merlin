# Merlin — Codex Handoff Context

## What This Is
macOS SwiftUI agentic chat app. Connects to DeepSeek V4 (remote) and LM Studio (local vision model). Full tool registry: file system, shell, Xcode, GUI automation via AX + ScreenCaptureKit + CGEvent.

## Full Design
See `../architecture.md` and `../llm.md` for all decisions. Do not re-derive — implement exactly as specified.

## Rules (apply to every phase)
- Swift 5.10, macOS 14+, SwiftUI + Swift Concurrency (async/await, actors)
- No third-party packages (production targets)
- Non-sandboxed app — no sandbox entitlement
- OpenAI function calling wire format for all tools
- Every file must compile with zero warnings
- TDD: tests in MerlinTests/ pass before phase is complete

## Project Layout
```
Merlin.xcodeproj
├── Merlin/                    (main app target)
│   ├── App/
│   ├── Providers/
│   ├── Engine/
│   ├── Auth/
│   ├── Tools/
│   ├── Sessions/
│   ├── Keychain/
│   └── Views/
├── MerlinTests/               (unit + integration, no network)
├── MerlinLiveTests/           (real DeepSeek + LM Studio — manual scheme)
├── MerlinE2ETests/            (full loop + visual — manual scheme)
└── TestTargetApp/             (fixture SwiftUI app for GUI automation tests)
```

## Model IDs
- `deepseek-v4-pro` — reasoning, long context
- `deepseek-v4-flash` — fast tool loops
- LM Studio: `Qwen2.5-VL-72B-Instruct-Q4_K_M` at `http://localhost:1234/v1`

## Prerequisites (manual, one-time)
```bash
brew install xcodegen
# After phase-01: run xcodegen generate once to produce Merlin.xcodeproj
```

## Codex invocation
```bash
codex --model gpt-5.4-mini -q "$(cat phases/phase-NN.md)" --approval-mode auto
```

## Key constraints added after initial design
- All value types must conform to `Sendable` (Swift strict concurrency is ON)
- `ShellTool` has a `stream()` variant returning `AsyncThrowingStream<ShellOutputLine, Error>`
- `ToolDefinitions.all` has a fixed set of built-in tools; count is not enforced — use ToolRegistry for the live set
- `ContextManager` exposes `forceCompaction()` for test use
- `TestHelpers/` is a source folder included in all three test targets (not a separate target)
- Tool handlers are registered in `Merlin/App/ToolRegistration.swift`, called from `AppState.init`
