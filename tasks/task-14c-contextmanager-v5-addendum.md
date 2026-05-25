# Task 14c — ContextManager v5 Addendum

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete.
Working dir: ~/Documents/localProject/merlin

**Authoritative current spec.** Task 14b is outdated — read this document for the
complete current `ContextManager`. Task 14b documented the original v1 implementation
(basic compaction, `forceCompaction()` test hook). This document adds all v5 additions:
skill reinjection after compaction (task 60b) and pre-run auto-compaction (task 151b).
The current source in `Merlin/Engine/ContextManager.swift` is the definitive implementation.

---

## Changes vs. task-14b

### 1. Skill reinjection after compaction (Task 60b)

After each compaction pass, recently-invoked skills are re-injected so the
model retains their instructions across long sessions.

**New properties:**

```swift
private(set) var recentlyInvokedSkills: [Skill] = []

private let skillBudgetTokens = 25_000    // total budget for all reinjected skills
private let skillBudgetPerSkill = 5_000   // cap per individual skill section
```

**New methods:**

```swift
/// Records that a skill was invoked. Keeps the most-recently-used `compactionKeepRecentTurns`
/// skills, deduplicating by name (re-invoked skills move to front).
func recordSkillInvocation(_ skill: Skill)

/// Builds the [Skills]…[/Skills] system message block from the given skill list.
/// Filters disabled skill names. Respects skillBudgetPerSkill and skillBudgetTokens
/// budgets to keep the block inside a model's context window.
/// Returns an empty string when the visible list is empty.
func buildSkillReinjectionBlock(skills: [Skill], disabledNames: [String] = []) -> String
```

**Compaction change:** At the end of `compact(force:)`, after rebuilding
`messages`, the skill reinjection block is computed from `recentlyInvokedSkills`
filtered against `AppSettings.shared.disabledSkillNames`. If non-empty, it is
appended as a `.system` message.

**Output format:**
```
[Skills]
## <skill-name>
<skill-body>

## <skill-name>
<skill-body>
[/Skills]
```

---

### 2. Pre-run auto-compaction (Task 151b)

Prevents the model from starting a new non-continuation turn with a context
window already near its limit (> 10 000 estimated tokens), which caused
run-loop starvation on large projects.

**New property:**

```swift
/// Token count above which compactIfNeededBeforeRun fires automatically.
/// Kept well below a typical 32 K model context so the model has ample
/// output space even in long sessions.
let preRunCompactionThreshold = 10_000
```

**New method:**

```swift
/// Called by AgenticEngine.runLoop before appending the user message.
/// Compacts when the session has grown past preRunCompactionThreshold tokens
/// and the turn is not a continuation (continuations must preserve recent
/// tool results so the model can finish multi-step work).
func compactIfNeededBeforeRun(isContinuation: Bool)
```

`AgenticEngine.runLoop` calls this immediately before `context.append(userMessage)`.

---

### 3. TelemetryEmitter in compact()

Each compaction pass emits a `"context.compaction"` event with:
- `message_count_before`, `message_count_after`
- `tokens_before`, `tokens_after`
- `forced` (Bool)

---

### 4. `class` instead of `final class` (current code)

The current source uses `class ContextManager` (not `final`), allowing
test subclasses to override compaction behaviour. Task 14b specified
`final class` — this is a minor divergence introduced during refactoring.

---

## Full current implementation

See `Merlin/Engine/ContextManager.swift` (194 lines as of task 151b).

Key constants summary:
| Constant | Value | Purpose |
|---|---|---|
| `compactionThreshold` | 800 000 | Auto-compact on `append()` |
| `compactionKeepRecentTurns` | 20 | Recent turns never compacted |
| `skillBudgetTokens` | 25 000 | Total skill reinject budget |
| `skillBudgetPerSkill` | 5 000 | Per-skill section budget |
| `preRunCompactionThreshold` | 10 000 | Auto-compact before run |

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ContextManager|BUILD SUCCEEDED|BUILD FAILED'
```

## Commit
```bash
cd ~/Documents/localProject/merlin
git add tasks/task-14c-contextmanager-v5-addendum.md
git commit -m "Task 14c — ContextManager v5 addendum (skill reinjection + pre-run compaction)"
```
