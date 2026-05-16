# merlin-kicad-mcp — Claude Session Instructions

Read this file at the start of every session. These rules apply to all work in this
project. This is the project **constitution**.

---

## Project

`merlin-kicad-mcp` is the external **MCP server** for Merlin's v2.0 Electronics/KiCad
domain. It is a standalone macOS command-line process that wraps `kicad-cli` (KiCad 10),
KiCad's `.kicad_sch` / `.kicad_pcb` S-expression files, and the FreeRouting HTTP API
behind OpenAI-compatible tool contracts, and serves a `DomainManifest` so Merlin
registers it through `MCPDomainAdapter`.

Merlin already ships the entire **client** side (`Merlin/Electronics/` — `KiCadMCPClient`,
`KiCadToolDefinitions`, the `.kicad_sch` parser, schemas, workflow orchestrator). This
project builds the **server** the client connects to. The tool contract is therefore
already ~80% pinned by the Merlin client and by `architecture.md` §2241–2263 in the
Merlin repo (`~/Documents/localProject/merlin/architecture.md`).

- Working directory: `~/Documents/localProject/merlin/plugins/merlin-kicad-mcp`
- Phase sheets: `phases/` — decomposition in `phases/ROADMAP.md`
- This package lives at `plugins/merlin-kicad-mcp/` **inside the Merlin repo** — it is
  tracked in that repo, not its own. The Merlin app (the client) is the rest of
  `~/Documents/localProject/merlin`.

---

## Non-Negotiable Rules (apply to every session)

- **TDD always.** Tests are written first (phase `NNa`), confirmed failing, then
  implementation follows (phase `NNb`). Never skip the failing-tests commit.
- **Git commit after every phase.** Each phase ends with an explicit `git add` +
  `git commit`. No exceptions — do not skip or batch commits across phases.
- **Zero warnings, zero errors.** Every file must compile clean.
  `SWIFT_STRICT_CONCURRENCY=complete` is on (set in `Package.swift`).
- **No third-party Swift packages.** MCP is JSON-RPC 2.0 over stdio — implement it with
  `Foundation` only (`JSONSerialization` / `JSONEncoder`, `FileHandle`, `Process`).
  No SwiftPM dependencies in `Package.swift`.
- **Phase files must stay in sync with the code.** Any code change — bug fix, refactor,
  new feature — must also update or create the relevant phase file(s) before the commit.
  A bug fix with no new surface adds a `## Fixes` section to the relevant `b` phase.

---

## Swift Standards

- Swift 5.10, macOS 14+, `async`/`await` + actors
- All value types crossing concurrency boundaries: conform to `Sendable`
- No force-unwraps, no `try!`, no `fatalError` in production code
- Parallel work: `async let` / `TaskGroup`, not sequential `await`

---

## Package Layout

```
merlin-kicad-mcp/
  Package.swift               — executable `merlin-kicad-mcp` + library `KiCadMCPKit`
  Sources/
    merlin-kicad-mcp/main.swift   — thin entry point; starts the server
    KiCadMCPKit/                  — all logic (transport, tools, KiCad/FreeRouting)
  Tests/
    KiCadMCPKitTests/             — XCTest unit tests
  phases/                     — phase sheets + ROADMAP.md
  CLAUDE.md  README.md  .gitignore
```

The executable target is thin; all logic and all tests live in `KiCadMCPKit`.

---

## Build Verification Commands

Use these exact commands for verification — do not invent variants:

```bash
# Build
swift build 2>&1 | grep -E 'error:|warning:|Compiling|Build complete' | tail -20

# Run tests
swift test 2>&1 | grep -E 'Test Case|passed|failed|error:' | tail -40
```

A phase `a` (failing tests) is expected to fail to build or fail at runtime — that is
the TDD signal. A phase `b` must build clean and pass all of its `a` phase's tests.

---

## Phase Sheet Format

Two-phase TDD pattern, identical to the Merlin project:

- `phases/phase-NNa-<name>-tests.md` — write the failing tests first.
- `phases/phase-NNb-<name>.md` — implement until the `NNa` tests pass.

Each phase file carries its own Context header, the full task, a Verify step, and an
explicit `git add` + `git commit`. See `phases/ROADMAP.md` for the full decomposition.

---

## Git Commit Protocol

Every phase ends with:

```bash
cd ~/Documents/localProject/merlin/plugins/merlin-kicad-mcp
git add <specific files — never git add -A>
git commit -m "kicad-mcp Phase NNx — <Description>"
```

Commits land in the **Merlin repo** (this package is a subdirectory of it) — prefix
every message with `kicad-mcp` so they read clearly alongside Merlin's own phases.
Never skip the commit. Never amend a prior phase commit. Never `git push` without an
explicit instruction.

---

## Key Constraints

- **MCP stdio transport** is newline-delimited JSON-RPC 2.0 — one JSON message per line
  on stdin/stdout, no embedded newlines. stderr is free for logging.
- **The `DomainManifest`** this server serves at `merlin://domain/manifest` must decode
  cleanly into Merlin's `DomainManifest` type (`Merlin/MCP/DomainPlugin.swift`) — id,
  displayName, taskTypes, highStakesKeywords, systemPromptAddendum, verificationCommands.
- **OpenAI function-calling wire format** for all tool definitions.
- **KiCad version gate:** every KiCad-touching tool requires `kicad-cli` major version
  ≥ 10; below that, return `BLOCKED_VERSION`.
- **`kicad-cli` is inside the app bundle** on macOS:
  `/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli` — it is not on `PATH`.
- **FreeRouting** is reached via its HTTP API (`https://api.freerouting.app/v1`), not a
  local install — it needs an API key.
- Never run destructive KiCad operations without the contract's approval/gate path.
