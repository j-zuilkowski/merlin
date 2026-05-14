# Phase 209b — KiCad MCP Tooling Boundary

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 209a complete: failing KiCad MCP tooling tests exist.

---

## Add: Merlin/Electronics/KiCadMCPTooling.swift

Implement:

1. `KiCadMCPServerConfig`
2. `KiCadMCPToolingStatus`
3. `KiCadVersionGate`
4. `KiCadToolExecutor`
5. `KiCadMCPToolExecutor`

Rules:

1. No real process launch in unit-test path.
2. Missing server/tooling maps to `.blockedTooling`.
3. KiCad major version `< 10` maps to `.blockedVersion`.
4. Tool results encode as `KiCadToolResult`.
5. Do not implement actual KiCad behavior in this phase; this phase creates the boundary.

---

## Edit: Merlin/Engine/ToolRouter.swift

Add `registerKiCadTools(executor:)`.

For every `KiCadToolDefinitions.requiredToolNames`, register a handler that:

1. passes the raw JSON argument string to `executor.execute(toolName:argumentsJSON:)`
2. encodes the `KiCadToolResult` as JSON
3. returns that JSON string to the agent

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. `KiCadMCPToolingTests` pass.

## Commit

```bash
git add Merlin/Electronics/KiCadMCPTooling.swift Merlin/Engine/ToolRouter.swift
git commit -m "Phase 209b — KiCad MCP tooling boundary"
```
