# Phase 142b — Semantic Fault Injection Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 142a complete: failing semantic fault injection tests in place.

Addresses the "semantic fault injection" mitigation from:
"Context Decay, Orchestration Drift, and the Rise of Silent Failures in AI Systems" — VentureBeat
https://venturebeat.com/infrastructure/context-decay-orchestration-drift-and-the-rise-of-silent-failures-in-ai-systems

---

## Write to: TestHelpers/SemanticFaults/StalenessInjectingMemoryBackend.swift

(Full content is in phase-142a — copy from there exactly.)

---

## Write to: TestHelpers/SemanticFaults/TruncatingMockProvider.swift

(Full content is in phase-142a — copy from there exactly.)

Note: `TruncatingMockProvider` must conform to `LLMProvider`. Check the existing
`LLMProvider` protocol definition in `Merlin/Providers/LLMProvider.swift` and ensure
all required properties and methods are implemented. If `LLMProvider` requires additional
fields (e.g. `capabilities`, `baseURL`), add them with sensible stub values.

---

## Write to: TestHelpers/SemanticFaults/EmptyToolResultRouter.swift

(Full content is in phase-142a — copy from there exactly.)

Note: `EmptyToolResultRouter` inherits from `ToolRouter`. Check whether `ToolRouter`
exposes a `call(tool:authPresenter:)` method that can be overridden. If `ToolRouter`
is a struct or final class, adjust the approach: wrap a `ToolRouter` instance and
delegate all methods, replacing the result in `call(tool:authPresenter:)`.

If `ToolRouter` cannot be subclassed, use composition:
```swift
struct EmptyToolResultRouter: ToolRouterProtocol {
    private let inner: ToolRouter
    init(registry: ToolRegistry) { inner = ToolRouter(registry: registry) }
    // delegate staging buffer, other properties to inner
    func call(tool: ToolCall, authPresenter: any AuthPresenter) async -> ToolResult {
        _ = await inner.call(tool: tool, authPresenter: authPresenter)
        return ToolResult(toolCallID: tool.id, content: "", isError: false)
    }
}
```
Adjust as needed to conform to whatever protocol `AgenticEngine` expects for its router.

---

## Write to: TestHelpers/SemanticFaults/DroppingContextManager.swift

(Full content is in phase-142a — copy from there exactly.)

Note: `DroppingContextManager` subclasses `ContextManager`. Check that `ContextManager`
is not marked `final` and that `buildMessages(systemPrompt:)` is overridable. If it is
final or if `AgenticEngine` uses a protocol for context management, adjust accordingly —
the intent is a context manager that silently discards old messages to simulate overflow.

---

## project.yml: add SemanticFaults sources to MerlinTests

The new TestHelpers files are in a subdirectory `TestHelpers/SemanticFaults/`.
If `project.yml` lists `TestHelpers/` as a source glob (e.g. `TestHelpers/**/*.swift`),
the files will be picked up automatically. If it lists files individually or uses a
non-recursive glob, add the subdirectory. After any `project.yml` change, run:
```bash
xcodegen generate
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED — all 142a tests pass, zero warnings.

## Commit
```bash
git add TestHelpers/SemanticFaults/StalenessInjectingMemoryBackend.swift
git add TestHelpers/SemanticFaults/TruncatingMockProvider.swift
git add TestHelpers/SemanticFaults/EmptyToolResultRouter.swift
git add TestHelpers/SemanticFaults/DroppingContextManager.swift
git commit -m "Phase 142b — semantic fault injection test doubles: stale retrieval, truncation, empty tools, context drop"
```
