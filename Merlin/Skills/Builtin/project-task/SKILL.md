# project:task

Build a TDD task pair (NNa + NNb) for a single well-scoped feature.

## Trigger

User says any of:
- "write a task for [feature]"
- "build a task pair for [feature]"
- "create the task files for [feature]"
- "/project:task"
- "scope a task pair for [feature]"

## Steps

1. **Determine the next task number**: Run `ls tasks/ | grep -E 'task-[0-9]+' | sort -V | tail -1`
   to find the highest number. Increment by 1.

2. **Ask structuring questions** (do not decompose automatically):
   - What is the single abstraction this task introduces? (One noun phrase.)
   - What prior task state does this depend on?
   - List every new type / method / property NNb will introduce.
   - List every deletion NNb performs (regression-guard tests will be added automatically).
   - Does this task add any user-facing surfaces? (Required for Manual updates section.)
   - Is this version-bump-eligible? (No for feature tasks; yes only for release milestones.)

3. **Validate decomposition** with `PlannerEngine.refineStep` (v2.1 feature):
   - Single concern? If scope covers two abstractions, split.
   - Tests precede implementation? (NNa must be committed before NNb.)
   - Deletions guarded? (If NNb deletes a symbol, a regression-guard test must exist in NNa.)

4. **Write task NNa** (`tasks/task-NNa-<name>-tests.md`):
   - Context block with prior-task state summary.
   - `## Traceability` block with:
     - `Vision reference: vision.md#<active-or-promoted-item>`
     - `Spec reference: spec.md#<committed-design-section>`
   - `## Behavior` block with EARS acceptance criteria. Use one or more
     `WHEN [trigger] THE [system] SHALL [response]` statements; use `WHILE`,
     `IF ... THEN`, or `WHERE` forms when they fit better.
   - "New surface introduced in task NNb:" listing every surface.
   - Full Swift test file content for every test case described in structuring questions.
   - Verify block: expected **BUILD FAILED** with missing-symbol errors.
   - Commit block: `git add` specific files, `git commit -m "Task NNa — <TestNames> (failing)"`.

5. **Write task NNb** (`tasks/task-NNb-<name>.md`):
   - Context block updated to "Task NNa complete."
   - Same `## Traceability` references as NNa.
   - `## Behavior` block restating the accepted behavior NNb implements.
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
