# Task 226b - KiCad MCP Real Executor

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 226a complete: failing KiCad MCP real executor tests exist.

---

## Add: Merlin/Electronics/KiCadMCPClient.swift

Define a `@MainActor` or actor-isolated client protocol and default implementation for invoking KiCad MCP tools through the existing MCP bridge.

Rules:

1. Keep unit tests fake-client only.
2. Preserve OpenAI function-calling wire format.
3. Decode MCP tool payload into `KiCadToolResult`.
4. Surface malformed payloads as `.blockedTooling` with warning details.

---

## Edit: Merlin/Electronics/KiCadMCPTooling.swift

Update `KiCadMCPToolExecutor`:

1. Add a client dependency.
2. Preserve existing server/tool/version gate behavior.
3. On success, call the client.
4. Return decoded client result.
5. Remove synthetic `kicad_boundary_stub` artifact generation.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. KiCad MCP real executor tests pass.

## Commit

```bash
git add Merlin/Electronics/KiCadMCPClient.swift Merlin/Electronics/KiCadMCPTooling.swift MerlinTests/Unit/KiCadMCPRealExecutorTests.swift
git commit -m "Task 226b - KiCad MCP real executor"
```

