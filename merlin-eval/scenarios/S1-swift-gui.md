# S1 — Swift GUI Debug Cycle

Proves Merlin can build a SwiftUI macOS app, run it, exercise its GUI (AX + screenshot),
detect logic **and** visual defects, fix them, rebuild, and re-verify.

---

## Fixture: `TaskBoard`

Location: `merlin-eval/fixtures/swift-gui-buggy/`

A small SwiftUI macOS app — a task list. **Build the correct app first, snapshot it to
`golden/`, then inject the eight defects below into the working copy.** `golden/` is the
diff reference for scoring; it is never given to Merlin.

### Intended (correct) behaviour
- `TaskBoardApp` — `@main`; a main `WindowGroup` showing `ContentView`, plus a second
  `WindowGroup(id: "stats")` showing `StatsView`. A `TaskStore` is created once and
  injected via `.environmentObject` into **both** scenes.
- `TaskStore` — `@MainActor final class TaskStore: ObservableObject`, `@Published var
  tasks: [TaskItem]`; `add(title:)`, `delete(at:)`, `toggleDone(_:)`.
- `TaskItem` — `Identifiable`: `id`, `title`, `isDone`.
- `ContentView` — a text field + Add button; the task list; a header reading
  `"<n> of <total> done"`; a toolbar button that opens the Stats window.
- `TaskRowView` — a checkbox, the title, a delete button. A done task shows the title
  struck through and in secondary grey.
- `StatsView` — reads the `TaskStore` from the environment; shows counts.
- A bundled test target `TaskBoardTests` with tests asserting correct `TaskStore`
  behaviour (these PASS on the correct app, FAIL once the logic defects are injected).

### Planted-defect manifest

| ID | Kind | Location | Defect | Expected fix | Detection cue |
|----|------|----------|--------|--------------|---------------|
| **L1** | logic / crash | `TaskBoardApp.swift` — the `WindowGroup(id:"stats")` scene | `StatsView()` is rendered without `.environmentObject(store)`; `StatsView` has `@EnvironmentObject var store` → opening the Stats window crashes (`EnvironmentObject.error`) | Inject `.environmentObject(store)` into the stats scene | Open the Stats window → app crashes |
| **L2** | logic | `TaskStore.summary` (shown verbatim in the ContentView header) | Summary shows `tasks.count` instead of `tasks.filter(\.isDone).count` for the "done" number | Use the filtered count | Header reads "3 of 3 done" when only 1 is checked; `testSummaryCountsDoneOnly` fails |
| **L3** | logic | `TaskStore.swift` — `delete(at:)` | Off-by-one: `tasks.remove(at: index + 1)` | `remove(at: index)` | Deleting a row removes the wrong task; `TaskBoardTests` deletion test fails |
| **L4** | logic | `TaskStore.swift` — async seed load | The initial-tasks load sets `tasks` off the main actor / without `await MainActor.run` (a data race / purple-runtime warning) | Hop to the main actor before mutating `@Published` | Thread Sanitizer / runtime warning; intermittent missing seed rows |
| **L5** | logic / dead control | `ContentView.swift` — toolbar "Clear Completed" button | The button exists and is tappable but its action body is empty `{ }` | Wire it to `store.tasks.removeAll { $0.isDone }` | Clicking "Clear Completed" does nothing |
| **V1** | visual | `TaskRowView.swift` | Row uses `HStack` with no `Spacer()` — checkbox, title, delete button bunch at the left | Add a `Spacer()` so the delete button is right-aligned | Screenshot: delete buttons not aligned to the trailing edge |
| **V2** | visual | `TaskRowView.swift` — title `Text` | `.frame(width: 80)` on the title → long titles clip | Remove the fixed width / use `.frame(maxWidth: .infinity, alignment: .leading)` | Screenshot: titles truncated mid-word |
| **V3** | visual | `TaskRowView.swift` — done styling | A completed task's title is coloured `.red` instead of `.secondary` | Use `.foregroundStyle(.secondary)` for done tasks | Screenshot: completed tasks are red, not grey |

Five logic + three visual = eight defects. L4 is intentionally subtle (concurrency).

---

## Scenario prompt (given to Merlin)

> The macOS app at `merlin-eval/fixtures/swift-gui-buggy/` is a SwiftUI task list called
> TaskBoard. This is a bounded GUI-debug repair task, not a tool-installation task.
> `xcodegen` is already available on PATH; do not use Homebrew, curl, or downloaded tool
> archives. Run `xcodegen generate`, then run `xcodebuild -scheme TaskBoard test
> -destination 'platform=macOS' CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO
> CODE_SIGNING_ALLOWED=NO`. Fix the app source defects named by failing TaskBoardTests,
> especially `TaskStoreTests.testDeleteRemovesTheTaskAtThatIndex` and
> `TaskStoreTests.testSummaryCountsDoneOnly`. Re-run the same verification until
> TaskBoardTests pass. Do not report done while any TaskBoardTests failure remains.
> Report each defect, the source fix, and the green verification command.

---

## Scoring rubric

**Deterministic (harness-checkable):**
- [ ] Fixture builds clean before and after Merlin's work (zero errors).
- [ ] `TaskBoardTests` — fails on the injected app (L2, L3), passes after Merlin's fixes.
- [ ] App launches and the Stats window opens without crashing (L1 fixed).
- [ ] "Clear Completed" removes done tasks (L5 fixed).
- [ ] No Thread Sanitizer / main-actor runtime warning on launch (L4 fixed).
- [ ] Final source diff vs. `golden/` touches only the eight defect sites — no unrelated churn.

**Judgment (human or Merlin vision-model judge, from screenshots):**
- [ ] V1 — delete buttons right-aligned.
- [ ] V2 — long titles fully visible, not clipped.
- [ ] V3 — completed tasks rendered in secondary grey, struck through — not red.
- [ ] Merlin's debugging was sound — it exercised the app, localised each bug, didn't
      guess. Review the transcript.

**Score:** defects fixed / 8, plus a pass/fail on "no unrelated churn" and "sound process".

---

## Runsheet

1. Ensure Batches B–D are merged and Merlin is built (`build/Debug/Merlin.app`).
2. Confirm LM Studio is running with both models; DeepSeek key present.
3. Build the fixture once to confirm it compiles; run `TaskBoardTests` and record which
   tests fail (expect the L2/L3 tests red).
4. Launch Merlin, open the `swift-gui-buggy` fixture as the project.
5. Paste the scenario prompt. **Dictation cue:** instead of pasting, press the mic button
   and *speak* the prompt — confirm transcription is accurate before sending (exercises S3).
6. Let Merlin run. Watch it build, launch the app, take screenshots, drive the GUI.
7. When it reports done: run `TaskBoardTests`, launch the app yourself, open Stats, click
   every button, eyeball the layout.
8. Score against the rubric. Write the result to `merlin-eval/results/S1-<date>.md`.
9. If Merlin missed or mis-fixed a defect, that is a finding — record it; it feeds the
   Merlin backlog.
