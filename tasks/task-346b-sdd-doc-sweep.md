# Task 346b — SDD Documentation Sweep

## Context

Task 346a added the stale-reference sweep. This task completes the repo-wide vocabulary
cleanup across active docs, prompts, historical task sheets, comments, tests, and helper
scripts.

## Behavior

WHEN the repository is scanned for retired SDD artifact names THE system SHALL report no
stale references.

WHEN historical implementation sheets are retained THE system SHALL use the current
`tasks/` filenames and task vocabulary.

## Implementation

- Updated active docs, prompts, release notes, eval docs, plugin scaffold docs, task
  sheets, code comments, and tests to use `constitution.md`, `spec.md`, `tasks/`, and
  task vocabulary.
- Renamed historical task-sheet filenames that still carried retired loader/scanner
  vocabulary.
- Encoded negative assertions in cutover tests without leaving stale literal references
  in tracked text.

## Verify

Run:

```bash
rg -n "retired SDD reference pattern" # implemented by SDDDocumentationSweepTests
xcodebuild -scheme MerlinTests \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  SYMROOT=build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_HARDENED_RUNTIME=NO \
  -only-testing:MerlinTests/SDDDocumentationSweepTests \
  -only-testing:MerlinTests/SDDArtifactCutoverTests \
  -only-testing:MerlinTests/ProjectTaskSkillCutoverTests \
  test
```

Expected: all SDD cutover and sweep tests pass.

## Commit

```bash
git add -A
git commit -m "Task 346b — SDD documentation sweep"
```
