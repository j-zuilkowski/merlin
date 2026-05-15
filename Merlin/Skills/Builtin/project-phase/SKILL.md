# project:phase

Build a TDD phase pair (NNa + NNb) for a single well-scoped feature.

## Trigger

User says any of:
- "write a phase for [feature]"
- "build a phase pair for [feature]"
- "create the phase files for [feature]"
- "/project:phase"
- "phase out [feature]"

## Steps

1. **Determine the next phase number**: Run `ls phases/ | grep -E 'phase-[0-9]+' | sort -V | tail -1`
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

4. **Write phase NNa** (`phases/phase-NNa-<name>-tests.md`):
   - Context block with prior-phase state summary.
   - "New surface introduced in phase NNb:" listing every surface.
   - Full Swift test file content for every test case described in structuring questions.
   - Verify block: expected **BUILD FAILED** with missing-symbol errors.
   - Commit block: `git add` specific files, `git commit -m "Phase NNa — <TestNames> (failing)"`.

5. **Write phase NNb** (`phases/phase-NNb-<name>.md`):
   - Context block updated to "Phase NNa complete."
   - Full implementation file content (or precise edit instructions for existing files).
   - If user-facing surfaces: add `## Manual updates` section listing sections to add/modify.
   - Verify block: expected **BUILD SUCCEEDED** + all NNa tests pass.
   - Commit block: `git add` specific files, `git commit -m "Phase NNb — <FeatureName>"`.

6. **Update PASTE-LIST.md**: append the new phase pair under the relevant milestone section.

7. **Handoff message**: summarise the two files written, the surfaces introduced, and the
   build command to run next.

## Output

- `phases/phase-NNa-<name>-tests.md`
- `phases/phase-NNb-<name>.md`
- PASTE-LIST.md updated
- No code written — only phase documents.

## Constraints

- NNa must compile but BUILD FAIL due to missing symbols. Verify section must state this.
- NNb must BUILD SUCCEED and all NNa tests must pass.
- xcodebuild commands must include code-signing bypass flags (see CLAUDE.md).
- Never batch two distinct features into one phase pair.
- `git add` must list specific files — never `git add -A`.
