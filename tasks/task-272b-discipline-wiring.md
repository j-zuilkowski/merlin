# Task 272b — Discipline App Integration Wiring

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 272a complete: failing tests for the discipline wiring.

This task wires the v2.2 discipline subsystem into the running app. Before this task
the subsystem ships but never executes. After it: `AppState` builds a `DisciplineEngine`
and a `PendingAttentionViewModel` at init, installs seed adapters, runs the SessionStart
hook, scans after every turn, and `ChatView` shows the pending-attention chip.

The discipline subsystem is opt-in per project — these edits are additive and must not
change behaviour for sessions on projects without `.merlin/`.

---

## Edit: Merlin/App/AppState.swift

### 1. Add stored properties

After the existing `@Published var engine: AgenticEngine!` group (near the other
`@Published` declarations), add:

```swift
    /// v2.2 Project Discipline Subsystem — central scanner coordinator. Built in init.
    let disciplineEngine: DisciplineEngine
    /// View-model backing the pending-attention chip + panel in ChatView.
    @Published var pendingAttention: PendingAttentionViewModel
```

### 2. Build them in `init`

`disciplineEngine` and `pendingAttention` are non-optional `let`/`@Published`
properties, so they MUST be assigned before `init` returns and before any method that
uses `self` is called. Build them immediately after `projectPath` is resolved — place
this block right after `self.activeDomainIDs = self.initialActiveDomainIDs` and before
`authMemory = AuthMemory(...)`:

```swift
        // --- v2.2 Project Discipline Subsystem ---
        // Built early so the non-optional stored properties are initialised before any
        // self-using call. The pending-attention queue persists to <project>/.merlin.
        let disciplineStorePath = (projectPath.isEmpty
            ? FileManager.default.temporaryDirectory.path
            : projectPath) + "/.merlin/pending.json"
        let disciplineQueue = PendingAttentionQueue(storePath: disciplineStorePath)
        // The seed adapters are installed asynchronously below; use the Swift stub as
        // the engine's adapter until a real .merlin/project.toml selection exists.
        let disciplineAdapter = ProjectAdapter.makeStub(language: "swift")
        disciplineEngine = DisciplineEngine(
            adapter: disciplineAdapter,
            taskScanner: TaskScanner(),
            manualCoverageScanner: ManualCoverageScanner(),
            docReferenceGraph: DocReferenceGraph(),
            whyCommentScanner: WhyCommentScanner(),
            proseReadabilityChecker: ProseReadabilityChecker(),
            storePath: disciplineStorePath
        )
        pendingAttention = PendingAttentionViewModel(queue: disciplineQueue)
```

### 3. Install seed adapters at launch

Inside the existing `Task { await AgentRegistry.shared.registerBuiltins() ... }` block
in `init` (the one that resolves `~/.merlin/agents`), OR as a new sibling `Task`, add
the seed-adapter install + load. A new sibling `Task` keeps the change isolated:

```swift
        Task {
            // Install + load the discipline seed adapters into ~/.merlin/adapters.
            let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
            let adaptersDir = "\(home)/.merlin/adapters"
            try? await AdapterRegistry.installSeedAdapters(into: adaptersDir)
            try? await AdapterRegistry.shared.loadFromDirectory(adaptersDir)
        }
```

### 4. Run the SessionStart hook and surface the note

Add a sibling `Task` in `init` (after the seed-adapter task is fine). It runs the
SessionStart hook for the open project and, if a note comes back, appends it as a
`.system` tool-log line so the user sees the top findings at session open:

```swift
        if !projectPath.isEmpty {
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let note = await HookEngine.shared.runSessionStart(
                    projectPath: projectPath) {
                    self.toolLogLines.append(ToolLogLine(
                        text: note, source: .system, timestamp: Date()))
                }
                // Refresh the chip from any persisted findings.
                await self.pendingAttention.refresh(projectPath: projectPath)
            }
        }
```

### 5. Scan after every turn

The `init` already stores a sink on `engine.$isRunning.filter { !$0 }` that resets
`toolActivityState`. Add a parallel sink (do NOT modify the existing one) that kicks a
discipline scan and refreshes the chip after each turn completes:

```swift
        // After every turn, run a discipline scan and refresh the pending-attention
        // chip. No-op for projects without a tasks/ or .merlin/ tree.
        engine.$isRunning
            .filter { !$0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.projectPath.isEmpty else { return }
                let path = self.projectPath
                Task { [weak self] in
                    guard let self else { return }
                    _ = await self.disciplineEngine.scan(projectPath: path)
                    await self.pendingAttention.refresh(projectPath: path)
                }
            }
            .store(in: &cancellables)
```

Place this immediately after the existing `engine.$isRunning ... .store(in: &cancellables)`
block.

---

## Edit: Merlin/Views/ChatView.swift

Embed `PendingAttentionChipView` in the chat `header`. The chip expands the
`PendingAttentionPanelView` it owns. In the `header` computed property, add the chip
just before `Spacer(minLength: 0)`:

```swift
            ProviderHUD()
            Spacer(minLength: 0)
            PendingAttentionChipView(viewModel: appState.pendingAttention)
```

If `PendingAttentionChipView`'s initializer differs (e.g. it takes an
`@ObservedObject` via a different label), match its actual signature from
`Merlin/Views/PendingAttentionChipView.swift` — the requirement is that `ChatView`
constructs `PendingAttentionChipView` bound to `appState.pendingAttention`.

`PendingAttentionChipView` only toggles `viewModel.isExpanded`; it does NOT present
the panel. `PendingAttentionPanelView` must be placed separately — it self-gates on
`isExpanded` (renders nothing when collapsed) and styles itself as a floating card,
so add it as a `.topTrailing` overlay on the `ChatView` body `VStack`:

```swift
        .overlay(alignment: .topTrailing) {
            PendingAttentionPanelView(
                viewModel: appState.pendingAttention,
                projectPath: appState.projectPath
            )
            .padding(.top, 56)
            .padding(.trailing, 12)
        }
```

---

## Fixes

- `AppState` gains `disciplineEngine` and `@Published pendingAttention`, both built in
  `init`. The pending-attention queue persists to `<projectPath>/.merlin/pending.json`.
- `AppState.init` installs + loads the seed adapters into `~/.merlin/adapters`, runs
  `HookEngine.shared.runSessionStart` for the open project (surfacing the note as a
  system tool-log line), and adds a post-turn `engine.$isRunning` sink that runs
  `disciplineEngine.scan()` and refreshes the chip.
- `ChatView` header embeds `PendingAttentionChipView` bound to
  `appState.pendingAttention`. The v2.2 subsystem is now live in the app.

### v2.2.4 — panel never placed (dead chip click)

The original wiring assumed the chip presented its own panel. It does not —
`PendingAttentionChipView` only toggles `viewModel.isExpanded`. Because
`PendingAttentionPanelView` was never instantiated anywhere in the app, clicking the
chip flipped `isExpanded` with no observer, so nothing happened. Fixed by adding the
`PendingAttentionPanelView` `.topTrailing` overlay to the `ChatView` body (see the
corrected ChatView edit above). Regression guard:
`MerlinTests/Unit/PendingAttentionPanelViewTests.swift`.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all task 272a tests pass. No prior task regresses.

**Manual confirmation (required, in addition to the automated tests):** build the app,
launch it (`open ~/Documents/localProject/merlin/build/Debug/Merlin.app`), open a
project that has a `.merlin/pending.json` with findings, and confirm the
pending-attention chip appears in the chat header and that expanding it shows the
panel.

## Commit

```bash
git add tasks/task-272b-discipline-wiring.md \
    Merlin/App/AppState.swift \
    Merlin/Views/ChatView.swift
git commit -m "Task 272b — Discipline app integration wiring"
```
