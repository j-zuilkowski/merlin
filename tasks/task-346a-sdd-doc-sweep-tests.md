# Task 346a — SDD Documentation Sweep Tests

## Context

The runtime and project skills now use the SDD artifact names. The remaining risk is
stale documentation, historical task-sheet content, prompts, release notes, and examples
that still point users or future agents at old artifact names.

## Behavior

WHEN the repository is swept for SDD terminology THE system SHALL reject stale artifact
names and stale construction vocabulary outside the explicit negative assertions in the
cutover tests.

WHEN historical implementation sheets are retained THE system SHALL use task filenames
and task vocabulary.

## Test Scope

Write failing tests in `MerlinTests/Unit/SDDDocumentationSweepTests.swift`.

The tests must scan tracked text files and fail on the retired instruction filename,
retired loader symbol, retired design filename, retired task directory, retired task
filename prefix, retired project construction command, retired skill path, and the
standalone retired task vocabulary word.

The test may exclude itself and the explicit negative-assertion cutover tests, but should
otherwise cover docs, task files, code comments, skills, prompts, scripts, and release
notes.

## Verify

Run:

```bash
xcodegen generate
xcodebuild -scheme MerlinTests \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  SYMROOT=build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_HARDENED_RUNTIME=NO \
  -only-testing:MerlinTests/SDDDocumentationSweepTests \
  test
```

Expected: tests fail until the repo-wide stale-reference sweep is complete.

## Commit

```bash
git add tasks/task-346a-sdd-doc-sweep-tests.md MerlinTests/Unit/SDDDocumentationSweepTests.swift
git commit -m "Task 346a — SDD documentation sweep tests"
```
