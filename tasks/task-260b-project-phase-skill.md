# Phase 260b — project:phase Skill

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 260a complete: failing tests asserting project:phase SKILL.md exists.

---

## Write to

### ~/.merlin/skills/project-task/SKILL.md

```bash
mkdir -p ~/.merlin/skills/project-task
```

File content:

```markdown
# project:phase

Build a TDD task pair (NNa + NNb) for a single well-scoped feature.

## Trigger

User says any of:
- "write a phase for [feature]"
- "build a task pair for [feature]"
- "create the task files for [feature]"
- "/project:task"
- "phase out [feature]"

## Steps

1. **Determine the next phase number**: Run `ls tasks/ | grep -E 'task-[0-9]+' | sort -V | tail -1`
   to find the highest number. Increment by 1.

2. **Ask structuring questions** (do not decompose automatically):
   - What is the single abstraction this phase introduces? (One noun phrase.)
   - What prior phase state does this depend on?
   - List every new type / method / property NNb will introduce.
   - List every deletion NNb performs (regression-guard tests will be added automatically).
   - Does this phase add any user-facing surfaces? (Required for Manual updates section.)
   - Is this version-bump-eligible? (No for feature phases; yes only for release milestones.)

3. **Validate decomposition** with `PlannerEngine.refineStep` (v2.1 feature):
   - Single concern? If scope covers two abstractions, split.
   - Tests precede implementation? (NNa must be committed before NNb.)
   - Deletions guarded? (If NNb deletes a symbol, a regression-guard test must exist in NNa.)

4. **Write phase NNa** (`tasks/task-NNa-<name>-tests.md`):
   - Context block with prior-phase state summary.
   - "New surface introduced in phase NNb:" listing every surface.
   - Full Swift test file content for every test case described in structuring questions.
   - Verify block: expected **BUILD FAILED** with missing-symbol errors.
   - Commit block: `git add` specific files, `git commit -m "Phase NNa — <TestNames> (failing)"`.

5. **Write phase NNb** (`tasks/task-NNb-<name>.md`):
   - Context block updated to "Phase NNa complete."
   - Full implementation file content (or precise edit instructions for existing files).
   - If user-facing surfaces: add `## Manual updates` section listing sections to add/modify.
   - Verify block: expected **BUILD SUCCEEDED** + all NNa tests pass.
   - Commit block: `git add` specific files, `git commit -m "Phase NNb — <FeatureName>"`.

6. **Update PASTE-LIST.md**: append the new task pair under the relevant milestone section.

7. **Handoff message**: summarise the two files written, the surfaces introduced, and the
   build command to run next.

## Output

- `tasks/task-NNa-<name>-tests.md`
- `tasks/task-NNb-<name>.md`
- PASTE-LIST.md updated
- No code written — only phase documents.

## Constraints

- NNa must compile but BUILD FAIL due to missing symbols. Verify section must state this.
- NNb must BUILD SUCCEED and all NNa tests must pass.
- xcodebuild commands must include code-signing bypass flags (see constitution.md).
- Never batch two distinct features into one task pair.
- `git add` must list specific files — never `git add -A`.
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all phase 260a `ProjectPhaseSkillTests` pass.

## Commit

```bash
git add tasks/task-260b-project-task-skill.md
git commit -m "Phase 260b — project:phase skill (SKILL.md)"
```
