# Task 260b — project:task Skill

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 260a complete: failing tests asserting project:task SKILL.md exists.

---

## Write to

### ~/.merlin/skills/project-task/SKILL.md

```bash
mkdir -p ~/.merlin/skills/project-task
```

File content:

```markdown
# project:task

Build a TDD task pair (NNa + NNb) for a single well-scoped feature.

## Trigger

User says any of:
- "write a task for [feature]"
- "build a task pair for [feature]"
- "create the task files for [feature]"
- "/project:task"
- "task out [feature]"

## Steps

1. **Determine the next task number**: Run `ls tasks/ | grep -E 'task-[0-9]+' | sort -V | tail -1`
   to find the highest number. Increment by 1.

2. **Ask structuring questions** (do not decompose automatically):
   - What is the single abstraction this task introduces? (One noun phrase.)
   - What prior task state does this depend on?
   - List every new type / method / property NNb will introduce.
   - List every deletion NNb performs (regression-guard tests will be added automatically).
   - Does this task add any user-facing surfaces? (Required for Manual updates section.)
   - Is this version-bump-eligible? (No for feature  tasks; yes only for release milestones.)

3. **Validate decomposition** with `PlannerEngine.refineStep` (v2.1 feature):
   - Single concern? If scope covers two abstractions, split.
   - Tests precede implementation? (NNa must be committed before NNb.)
   - Deletions guarded? (If NNb deletes a symbol, a regression-guard test must exist in NNa.)

4. **Write task NNa** (`tasks/task-NNa-<name>-tests.md`):
   - Context block with prior-task state summary.
   - "New surface introduced in task NNb:" listing every surface.
   - Full Swift test file content for every test case described in structuring questions.
   - Verify block: expected **BUILD FAILED** with missing-symbol errors.
   - Commit block: `git add` specific files, `git commit -m "Task NNa — <TestNames> (failing)"`.

5. **Write task NNb** (`tasks/task-NNb-<name>.md`):
   - Context block updated to "Task NNa complete."
   - Full implementation file content (or precise edit instructions for existing files).
   - If user-facing surfaces: add `## Manual updates` section listing sections to add/modify.
   - Verify block: expected **BUILD SUCCEEDED** + all NNa tests pass.
   - Commit block: `git add` specific files, `git commit -m "Task NNb — <FeatureName>"`.

6. **Update PASTE-LIST.md**: append the new task pair under the relevant milestone section.

7. **Handoff message**: summarise the two files written, the surfaces introduced, and the
   build command to run next.

## Output

- `tasks/task-NNa-<name>-tests.md`
- `tasks/task-NNb-<name>.md`
- PASTE-LIST.md updated
- No code written — only task documents.

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

Expected: **BUILD SUCCEEDED** and all task 260a `ProjectTaskSkillTests` pass.

## Commit

```bash
git add tasks/task-260b-project-task-skill.md
git commit -m "Task 260b — project:task skill (SKILL.md)"
```
