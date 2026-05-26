# Task 209a — KiCad MCP Tooling Boundary Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 208b complete: KiCad v2.0 core contracts and tool schemas exist.

New surface introduced in task 209b:
  - `KiCadMCPServerConfig` — server path, KiCad CLI path, FreeRouting path, required tool names
  - `KiCadMCPToolingStatus` — local tooling availability/capability report
  - `KiCadToolExecutor` protocol — typed async execution boundary for `kicad_*` tools
  - `KiCadMCPToolExecutor` — validates server/tool availability and maps failures to `KiCadToolResult`
  - `KiCadVersionGate` — parses KiCad CLI version output and enforces `>= 10`
  - `KiCadToolRegistration` — registers KiCad handlers in `ToolRouter` without implementing domain behavior yet

TDD coverage:
  File 1 — `KiCadMCPToolingTests`: version parsing, version blocking, missing server/tool blocking, JSON result envelope, ToolRouter handler registration

---

## Write to: MerlinTests/Unit/KiCadMCPToolingTests.swift

Create tests that assert:

1. `KiCadVersionGate.parseMajorVersion(from: "KiCad Version: 10.0.1") == 10`
2. `KiCadVersionGate.evaluate(versionOutput: "KiCad Version: 9.0.0", requiredMajor: 10)` returns `BLOCKED_VERSION`
3. `KiCadMCPToolExecutor` with unavailable server returns `KiCadToolResult(status: .blockedTooling)` and a `KICAD_MCP_UNAVAILABLE` warning/violation code
4. `KiCadMCPToolExecutor` with missing required tool returns `.blockedTooling`
5. `ToolRouter.registerKiCadTools(executor:)` registers at least `kicad_check_version`, `kicad_ingest_schematic`, `kicad_route_pass`, `kicad_export_fab`
6. Registered handlers return JSON that decodes as `KiCadToolResult`

Use a local fake executor; do not launch real KiCad or MCP processes.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with missing symbols for the task 209b surface.

## Commit

```bash
git add MerlinTests/Unit/KiCadMCPToolingTests.swift
git commit -m "Task 209a — KiCadMCPToolingTests (failing)"
```
