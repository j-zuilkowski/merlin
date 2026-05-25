# Task 279 — Gate the project:* skill tests for CI

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 278 task files exist but are not yet executed.

This is a **cleanup task** (single task file — no NNa/NNb pair).

**The problem.** GitHub CI run `25931330112` (the `152654d` push) failed: 25 tests
across 5 suites — `ProjectInitSkillTests`, `ProjectTaskSkillTests`,
`ProjectReviseSkillTests`, `ProjectReleaseSkillTests`, `ProjectAdoptSkillTests` — all
fail with `~/.merlin/skills/project-<name>/SKILL.md not found`.

Those suites assert that the `project:*` SKILL.md files exist at
`~/.merlin/skills/project-<name>/SKILL.md`. The skill  tasks 259b–263b *install* those
files into the user's HOME directory; they are never committed to the repository. A
clean CI runner (or any fresh machine) has an empty `~/.merlin/skills/`, so the suites
cannot pass there. They are environment-dependent in exactly the way the engine suites
gated in task 274b were — they were simply missed, because the 274b gate list was
built from the v2.1.0 CI run, which predates these v2.2 skill tests.

**The fix.** Gate all five skill-test suites behind the existing
`skipUnlessLiveEnvironment()` helper (`TestHelpers/LiveEnvironmentGate.swift`, added in
274b). Every test in each of these suites depends on the installed skill file, so gate
at the **suite level** in `setUpWithError()` — not per-method.

**Run this task before task 278.** Task 278b's verify expects the full suite green
headless; that holds only once these suites are gated.

---

## Edit

For each of the five files below, add a `setUpWithError()` that gates the whole suite.
If the suite already has a `setUpWithError()`, prepend the gate call as its first
statement.

```swift
override func setUpWithError() throws {
    try skipUnlessLiveEnvironment(
        "project:* skill must be installed in ~/.merlin/skills")
}
```

Files:
- `MerlinTests/Unit/ProjectInitSkillTests.swift`
- `MerlinTests/Unit/ProjectTaskSkillTests.swift`
- `MerlinTests/Unit/ProjectReviseSkillTests.swift`
- `MerlinTests/Unit/ProjectReleaseSkillTests.swift`
- `MerlinTests/Unit/ProjectAdoptSkillTests.swift`

`skipUnlessLiveEnvironment()` throws `XCTSkip` unless `RUN_LIVE_TESTS=1`, so under a
headless CI run these 25 tests report as **skipped**; a developer with the skills
installed sets `RUN_LIVE_TESTS=1` to run them.

No other file changes. Do not delete the suites — they are valid checks where the
skills are installed.

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

Expected: **BUILD SUCCEEDED**, zero test failures. The five `Project*SkillTests` suites
report as **skipped** (RUN_LIVE_TESTS unset). This is the state GitHub CI will see —
a green run.

## Commit

```bash
git add tasks/task-279-skill-test-ci-gate.md \
    MerlinTests/Unit/ProjectInitSkillTests.swift \
    MerlinTests/Unit/ProjectTaskSkillTests.swift \
    MerlinTests/Unit/ProjectReviseSkillTests.swift \
    MerlinTests/Unit/ProjectReleaseSkillTests.swift \
    MerlinTests/Unit/ProjectAdoptSkillTests.swift
git commit -m "Task 279 — Gate project:* skill tests behind RUN_LIVE_TESTS for CI"
```

## Fixes

The five `project:*` skill-test suites assert SKILL.md files installed in the user's
HOME by  tasks 259b–263b. Those files are not committed to the repo, so the suites
failed on a clean GitHub CI runner (run `25931330112`). Gated them behind
`skipUnlessLiveEnvironment()`, consistent with the engine-test gate from task 274b.
