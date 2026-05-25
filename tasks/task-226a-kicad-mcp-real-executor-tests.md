# Task 226a - KiCad MCP Real Executor Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 209b intentionally created only a KiCad MCP tooling boundary and returns `kicad_boundary_stub` artifacts.

New surface introduced in task 226b:
  - `KiCadMCPClient` JSON-RPC client abstraction.
  - `KiCadMCPToolExecutor` delegates available tool calls to `KiCadMCPClient`.
  - Real executor returns artifact refs from MCP responses instead of stub `/tmp/<tool>.json` paths.

TDD coverage:
  File 1 - `KiCadMCPRealExecutorTests`: JSON-RPC delegation and result mapping.

---

## Add: MerlinTests/Unit/KiCadMCPRealExecutorTests.swift

Create tests with a fake `KiCadMCPClient`.

Assert:

1. `KiCadMCPToolExecutor.execute(toolName:arguments:)` calls the client with the same tool name and arguments.
2. Client JSON response maps to `KiCadToolResult`.
3. Returned artifact refs are preserved exactly.
4. Tooling/version gates still block before client execution.
5. The successful path does not synthesize `kicad_boundary_stub` artifacts.

No real KiCad, FreeRouting, process launch, or network.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because `KiCadMCPClient` and real result delegation do not exist.

## Commit

```bash
git add MerlinTests/Unit/KiCadMCPRealExecutorTests.swift
git commit -m "Task 226a - KiCadMCPRealExecutorTests (failing)"
```

