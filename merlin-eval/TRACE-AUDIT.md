# W4 — Trace-the-Calls Audit

Deep audit of the live Merlin codebase (258 Swift files under `Merlin/`).
Date: 2026-05-16. Repo HEAD: `819f3a1` (Task 319b). Scanner baseline: 220 findings
(214 `taskDrift`, 4 `docStaleReference`, 2 `stubbedImplementation`).

Method: followed call chains directly — did not trust green builds. Every `@EnvironmentObject`
consumer traced to its injecting ancestor; the two suspect subsystems (KAG, Telemetry)
traced symbol-by-symbol to production call sites; `DisciplineEngine.scan()` traced from
its registration site to runtime; the 220 scanner findings triaged group by group.

---

## Verdict summary

| # | Finding | Class | Action |
|---|---|---|---|
| F1 | `WorkerDiffView` "Reject All" / "Accept & Merge" buttons have empty `{ }` actions | **DEAD control** | Task 320a/320b |
| F2 | `spec.md` — stale `FindingCategory.versionBumpCandidate` + nonexistent `KAGTripleSource.domain` | **STALE doc** | Fixed directly (this session) |
| F3 | `DocReferenceGraph.extractEnumCaseNames` flags identifiers inside `//` comments | **Scanner false positive** | Task 321a/321b |
| F4 | `TaskScanner` reads only `task-NNb` docs — misses the `a`-tier "New surface" blocks (200 docs) + `diag-*` | **Scanner blind spot** | Task 323a/323b |
| F5 | `TelemetryEmitter.setSession/setTurn/setLoop` — no callers anywhere | **DEAD code** | Task 322 |
| F6 | `.environmentObject(sessionManager)` injected with no consumer (×2) | **Harmless over-injection** | No action |
| F7 | Task 319b left `DocReferenceDanglingTests` (2 of 3 tests) failing since it landed | **Test rot** | Folded into task 321b — see §8 |
| F8 | Task 323 exposed `TaskScanner`'s symbol matching as too crude — qualified names, enum cases, non-symbol backtick content (211 → 981 nudges) | **Scanner accuracy** | Task 324a/324b — see §9 |
| — | `@EnvironmentObject` injection wiring (23 consumers) | **VERIFIED CLEAN** | None — see §1 |
| — | `DisciplineEngine.scan()` at `AppState.swift:286` | **VERIFIED LIVE** | None — see §2 |
| — | KAG subsystem (8 public types) | **VERIFIED LIVE** | None — see §4 |

No runtime-crash defects were found. The `@EnvironmentObject` crash class that started
this effort is fully resolved.

---

## §1 — `@EnvironmentObject` injection audit (the crash class)

23 `@EnvironmentObject` consumers across 19 view files. Each consumed type was traced
to a `.environmentObject(...)` injection on a reachable ancestor in the live view tree.

**Workspace window** (`MerlinApp.swift:26` → `WorkspaceView`):
- `WorkspaceView` consumes `RecentProjectsStore` ← injected `MerlinApp.swift:28`.
- `SessionSidebar` consumes `WorkspaceCoordinator` ← injected `WorkspaceView.swift:22`.
- `ContentView` consumes `AppState` + `ProviderRegistry` ← injected `WorkspaceView.swift:83,:85`.
- `ChatView` consumes `AppState`/`SkillsRegistry`/`ChatViewModel` ← inherited through
  `ContentView`; also independently injected at `FloatingWindowManager.swift:146-150`
  and `SideChatPane.swift:28-32` (the two other `ChatView` instantiation sites).
- `SlotStatusPanel` (explicit slot assignments + registry display-name resolver),
  `ToolLogView` (`AppState`), `ScreenPreviewView` (`AppState`) — all descend from
  `ChatView`/`ContentView` or the workspace sidebar. ✓
- `SkillsPicker` consumes `SkillsRegistry` ← injected `ChatView.swift:213`.
- `ProjectPickerView` consumes `RecentProjectsStore` ← injected on its sheet
  `WorkspaceView.swift:66`. `FirstLaunchSetupView` consumes `AppState` ← injected on its
  sheet `ContentView.swift:54`. (Sheets re-inject explicitly — safe regardless of
  SwiftUI sheet-environment inheritance.) ✓

**Settings window** (`MerlinApp.swift:42` → `SettingsWindowView`, a separate scene):
- `SettingsWindowView` owns `appState` + `registry` as `@StateObject` (`:6-7`); injects
  `appState` on the whole detail tree (`:21`) and `registry` only on the three panes
  that need it — `.providers` (`:35`), `.roleSlots` (`:38`), `.agents` (`:41`).
- `registry` consumers — `AgentSettingsView` (`:240`), `RoleSlotSettingsView`,
  `ProviderSettingsView` (reached via `ProvidersSettingsView` on the `.providers` pane) —
  are all inside one of those three injected panes. ✓
- `scheduler` consumers — `SchedulerSettingsView` (`:432`), `SchedulerView` (`:4`),
  `AddScheduledTaskView` (`:83`) — inherit `scheduler` injected on the whole settings
  scene at `MerlinApp.swift:44`; the `.sheet` at `SchedulerView.swift:41` re-injects it. ✓
- `appState` consumers `MemoryBrowserView`, `PerformanceDashboardView` inherit from `:21`. ✓

**Verdict: CLEAN.** Every consumer has an injecting ancestor. No task doc needed.

---

## §2 — `DisciplineEngine.scan()` liveness

`disciplineEngine` is a `let` property of `AppState` (`AppState.swift:56`), constructed in
`init` (`:126`). The scan trigger is a Combine sink registered inside that same `init`
(`AppState.swift:278-291`): it subscribes to `engine.$isRunning`, filters to `!isRunning`,
and — guarded by `!projectPath.isEmpty` — calls `await disciplineEngine.scan(projectPath:)`
(line 286), then `runWeeklyOverrideReview()` and `pendingAttention.refresh()`.

- `AppState.init` runs once per `LiveSession` (`LiveSession.swift:56` constructs
  `AppState(projectPath: projectRef.path, …)` with a **real** project path).
- The sink therefore fires after every engine run completes, for any workspace session.
- The Settings window's `AppState(projectPath: "")` (`SettingsWindowView.swift:7`) hits
  the empty-path guard and never scans — correct, it has no project.

**Verdict: LIVE.** The discipline scan fires after every agent turn for any real session.

---

## §3 — Dead controls & stubs

`StubMarkerScanner` reports exactly **2 `stubbedImplementation` findings**, both confirmed:

**F1 — `WorkerDiffView.swift:39` and `:42`** — `Button("Reject All") { }` and
`Button("Accept & Merge") { }` have empty actions. They carry accessibility IDs
(`workerDiffRejectAllButton`, `workerDiffAcceptMergeButton`) so they look wired but do
nothing. The view already loads `entry.stagingBuffer` (an `actor StagingBuffer`) and
displays its entries. `StagingBuffer` exposes `rejectAll()` (sync, isolated) and
`acceptAll() async throws` — the working `DiffPane` view drives the identical
accept-all/reject-all pattern. **Fix authored: task 320a/320b.**

Other sweeps: `SettingsWindowView.swift:935` `Button("Cancel", role: .cancel) {}` — an
empty `.cancel`-role button is idiomatic SwiftUI (the dialog self-dismisses); the scanner
already skips it. No `fatalError`/`preconditionFailure`/`notImplemented`/`unimplemented`
in production paths. `// TODO` markers: only `ManualSectionTemplateWriter.swift:27`, which
is a template *string the scanner writes into generated docs* — not a code stub. No
genuine deferred-work stubs remain.

---

## §4 — Subsystem liveness (public type → call site)

### KAG — **LIVE**
`Merlin/KAG/` (5 files). All 8 public types reach production:
- `KAGEngine` — property of `AgenticEngine` (`AgenticEngine.swift:85`); `scheduleExtraction()`
  called post-turn at `AgenticEngine.swift:1395` (gated by `AppSettings.shared.kagEnabled`).
- `KAGBackendRegistry` / `XcalibreKAGPlugin` / `LocalKAGPlugin` / `NullKAGPlugin` — wired in
  `AppState.configureKAGBackend()` (`AppState.swift:841-870`, called from `init`).
- `KAGBackendPlugin.traverse()` → `[KAGTriple]` — called in `RAGTools.swift:33` for RAG
  context enrichment. `KAGTriple` / `KAGTripleSource` exercised along that path.

### Telemetry — **LIVE** (with 3 dead methods)
`Merlin/Telemetry/TelemetryEmitter.swift`. `TelemetryEmitter.shared.emit(…)` /
`emitGUIAction(…)` have ~96 production call sites across 24 files (engine, providers,
MCP, RAG, views). `TelemetryValue` / `TelemetryEvent` are exercised by every `emit`.
- **F5 — DEAD:** `setSession(_:)`, `setTurn(_:)`, `setLoop(_:)` have **no callers at
  all** — not production, not tests. (`setContext(…)` supersedes them and is test-only.)
- Test-only surface (not dead, but never hit in production): `TelemetrySpan`, `begin(_:)`,
  `finish(data:)`, `emitProcessMemory()`, `flushForTesting()`, `resetForTesting(…)`.

**Resolution:** the 3 dead setters are deleted by **task 322** (a repo-wide grep
confirmed zero callers in any target). `diag-01b` — the rebuild source for
`TelemetryEmitter` — is updated in the same task.

---

## §5 — `taskDrift` triage (214 findings)

Every flagged symbol was checked against the source tree and the `tasks/` directory.
**None of the 214 indicates dead, broken, or mis-wired code.** Breakdown:

| Group | Count | Root cause | Class |
|---|---|---|---|
| `AccessibilityID` enum + ~155 `let …Button`/`…Field` constants | ~157 | introduced in `diag-07b-accessibility.md` | Scanner blind spot |
| Telemetry types/methods | ~22 | introduced in `diag-01b-telemetry-emitter.md` | Scanner blind spot |
| KAG types/methods | ~30 | `task-19{0,1,2}b` carry no "New surface" block | Task-doc format gap |
| `let shared` ×3 | 3 | generic singleton accessor name | Normalization noise |
| `(block) git add` | 1 | a back-ticked git command parsed as a "surface" | Parser false positive |

**F4 — `TaskScanner` reads the wrong doc tier.** `TaskScanner.extractDeclaredSurfaces`
(`TaskScanner.swift:91-97`) only reads files matching the regex `task-\d+b-`. But the
`New surface introduced in task` block — the only thing it harvests declared surfaces
from — lives in the **`a` (tests) doc** per the `constitution.md` template. A grep of `tasks/`
confirms it: **200 of 263 `task-*a-*.md` carry the block versus 8 of 266
`task-*b-*.md`.** The `diag-*` series is excluded by the regex entirely. So the scanner
harvests ~9 docs' worth of declared surface out of ~200, `declaredNames` is nearly empty,
and every `public` symbol it cannot match is flagged `orange`. (It also explains the zero
`green`/`yellow` findings — there is almost nothing to match against.)

All 214 are `nudge` severity (advisory, non-blocking) and none is a code defect — but a
task-drift scanner that is structurally blind across ~200  tasks leaves the
"task files are the rebuild source of truth" invariant unverified, which is a real
latent risk. **Task 323 fixes it:** `TaskScanner` reads every task doc (`a`, `b`,
`diag-*`); and `DisciplineEngine` surfaces `red`/`yellow`/`orange` drift all as `.nudge`.
The severity change is load-bearing — once the scanner can see 200 historical task docs
it will find genuine `red` drift (symbols declared long ago and since refactored away),
and the old `red → .block` mapping would jam the live pre-commit gate on normal code
evolution. After 323 lands, the residual orange/yellow/red is the *true* task-doc drift
backlog — a triage task, surfaced rather than hidden.

---

## §6 — `docStaleReference` triage (4 findings, all in `spec.md`)

`DocReferenceGraph.danglingReferences` flags an enum `case` inside a fenced code block
whose name (≥4 chars) matches no source symbol.

- **`versionBumpCandidate`** — `spec.md:4933`, in the `enum FindingCategory`
  code block. **GENUINE STALE:** task 301 deleted `FindingCategory.versionBumpCandidate`;
  the doc block was missed. The block is also *missing* the three cases that exist today
  (`ungatedTarget`, `stubbedImplementation`, `unwiredComponent`).
- **`domain`** — `spec.md:622`, `case domain` in the `enum KAGTripleSource`
  example. **GENUINE STALE:** the shipped enum (`KAGTriple.swift`, task 190b) has only
  `session` and `book`; `domain` was a design-doc aspiration never implemented.
- **`shape`** — `spec.md:4546`. **SCANNER FALSE POSITIVE:** the word `shape`
  appears inside the `//` comment on `case green // surface present, shape unchanged`.
  `extractEnumCaseNames` comma-splits the line *without stripping the `//` comment first*,
  so ` shape unchanged` is parsed as a second "case."
- **`signature`** — `spec.md:4547`. **SCANNER FALSE POSITIVE:** identical cause —
  `case yellow // surface present, signature changed`.

**Actions:** F2 (the two genuine stale refs) — `spec.md` corrected directly this
session: `versionBumpCandidate` removed and the three real cases added; `KAGTripleSource`
example's `case domain` removed and its inline `// .session | .book | .domain` comment
fixed. F3 (the two false positives) — `DocReferenceGraph.extractEnumCaseNames` must strip
`//` comments before comma-splitting; **fix authored: task 321a/321b.**

---

## §7 — Minor findings

**F6 — `.environmentObject(sessionManager)` over-injection.** `SessionManager` is injected
at `FloatingWindowManager.swift:149` and `SideChatPane.swift:31` onto `ChatView`, but no
view consumes it via `@EnvironmentObject`. Harmless (an unused environment object never
crashes) — leave it, or drop the two lines as cosmetic cleanup. Not task-worthy.

**`(block) git add` taskDrift entry.** A back-ticked `git add …` command in some task
doc's bullet list is parsed by `TaskScanner` as a declared surface named `git`. Cosmetic
parser false positive; subsumed by the F4 scanner work.

---

## §8 — Test rot from task 319b (surfaced while executing 321b)

Task 319b deleted `DocReferenceGraph.danglingReferences`' loose backticked-identifier
check and — correctly — rewrote `DocReferenceGraphScopeTests` to suit. It **missed
`DocReferenceDanglingTests`**: that file's `testDanglingReferenceDetected` and
`testEngineEmitsOneFindingPerDanglingReference` fixture *prose* backtick mentions
(`NonExistentType`, `GhostType`), the exact pattern 319 stopped detecting. Both have
failed at runtime since 319b was committed (`819f3a1`).

It went unnoticed because 319b's Verify used `-only-testing` on three hand-picked classes
and never ran `DocReferenceDanglingTests` or the full suite. The W4 task 321b execution
caught it — 321b's Verify did list that class, and Codex correctly halted on the
mismatch rather than committing red.

**Resolution:** the `DocReferenceDanglingTests` rewrite (onto the surviving fenced-block
enum-case check) is folded into **task 321b §2** — the same in-task repair pattern 319b
used for `DocReferenceGraphScopeTests`. 321b's Verify now runs all seven `DocReference*`
test classes, not a subset, so a future loose-check change cannot rot a sibling unseen.

---

## Task docs authored (this session)

| Task | Title | Kind | Verify with |
|---|---|---|---|
| 320a | `WorkerDiffView` reject/accept tests (failing) | compile-failure | `build-for-testing` |
| 320b | Wire `WorkerDiffView` reject-all / accept-and-merge | implementation | `test` |
| 321a | `DocReferenceGraph` comment-stripping tests (failing) | runtime-failure | `test` |
| 321b | `DocReferenceGraph.extractEnumCaseNames` strips `//` comments | implementation | `test` |
| 322  | Remove 3 dead `TelemetryEmitter` setters (F5) | implementation (cleanup) | `build-for-testing` |
| 323a | TaskScanner doc-coverage + drift-severity tests (F4) | runtime-failure | `test` |
| 323b | TaskScanner reads all task docs; drift is always a nudge (F4) | implementation | `test` |
| 324a | TaskScanner symbol-matching accuracy tests (F8) | runtime-failure | `test` |
| 324b | TaskScanner symbol-matching accuracy (F8) | implementation | `test` |

Next free task number after this batch: **325**.

## §9 — F8: TaskScanner symbol-matching accuracy ( tasks 323 → 324)

Task 323 turned the scanner on — it now reads all ~200 task docs. The scan jumped
211 → 981, but ~900 of those were false positives from crude symbol matching, not real
drift: qualified names (`Type.member` in docs vs bare `member` in source), enum cases
(never enumerated from source at all), non-symbol backtick content (`/compact`, `2.1.0`,
`Notes.md`), and a `yellow` "signature drift" tier comparing free-form doc signatures.

Task 324 fixes the matching. **Verified** (full `MerlinTests` suite green — 1780 tests,
0 failures; scanner rebuilt; scan **981 → 252**):
- `canonicalDeclaration` strips declaration-kind keywords and leading `.`/`Type.`
  qualifiers; `enumerateSourceDeclarations` records enum `case` declarations;
  `extractSurfaces` ignores non-symbol backtick content.
- the unreliable `yellow` tier is removed — `red` = "declared symbol absent" (the
  actionable signal), `green` = "present".

Post-324 the 252 are **61 red + 191 orange** (0 yellow). The red tier is now a real
signal — mostly genuine stale-doc drift, with a residual ~15 scanner edge cases (`init`
is not enumerated; build-setting names like `MARKETING_VERSION`; `$projected` values; a
`file.swift:lines` reference). The 191 orange is a task-doc *format* artifact, not
drift: ~155 are the `AccessibilityID` constants plus the KAG/Telemetry public surface,
which **are** task-documented — via `## Write to:` code fences rather than "New surface"
bullet blocks, which is all `extractSurfaces` harvests.

252 is a ~4× honest improvement over 981. Closing the residual fully is optional
follow-up (harvest declared symbols from `## Write to:` fences, or narrow the over-broad
`public` on the AX-ID catalogue) — diminishing returns versus the W5 eval suite.

## Re-scan trajectory

| Stage | `taskDrift` | other | total |
|---|---|---|---|
| W4 start | 214 | 6 (`docStaleReference` 4 + `stubbedImplementation` 2) | **220** |
| after 320–322 | 211 | 0 | **211** |
| after 323 (scanner reads all docs) | 981 | 0 | **981** |
| after 324 (matching fixed) | 252 | 0 | **252** |

Every W4 code/doc defect (F1, F2, F3, F7) is resolved and verified; F5 by task 322;
F4/F8 by  tasks 323–324. **All of  tasks 320–324 are committed** (`54f9dec`, `90560a2`,
`a11e595`, `66ebbb8`, `43c21d3`, `067bcfd`, `85878d0`, `9ea2dd3`, `6f4e0cb`). The
post-324 `252` (61 red + 191 orange, all nudge) is the real task-doc drift metric.
