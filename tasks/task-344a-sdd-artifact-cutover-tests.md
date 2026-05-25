# Task 344a — SDD Artifact Cutover Tests

## Context

Merlin is moving from the old Claude/architecture/phase vocabulary to its own SDD
artifact model. This task pins the red test contract for the hard cutover.

Canonical artifacts after the migration:

- `constitution.md`
- `spec.md`
- `tasks/`
- `tasks/task-*`

No compatibility layer is allowed for `constitution.md`, `spec.md`, `tasks/`, or
`task-*` as canonical project artifacts.

## Behavior

WHEN the repository is checked after the migration THE system SHALL contain the canonical
SDD root files and task directory.

WHEN the repository is checked after the migration THE system SHALL NOT retain legacy
canonical root files or the legacy phase directory.

WHEN Merlin loads project instructions THE system SHALL use constitution vocabulary and
symbols, not `Constitution` vocabulary.

WHEN the discipline scanner reads implementation history THE system SHALL scan `tasks/`
and `task-*` files as the canonical source of declared surfaces.

## Test Scope

Write failing tests in `MerlinTests/Unit/SDDArtifactCutoverTests.swift`.

The tests must assert:

- root artifact names are `constitution.md`, `spec.md`, and `tasks/`;
- `constitution.md`, `spec.md`, and `tasks/` are no longer present as canonical root
  artifacts;
- `ConstitutionLoader.swift` exists and `ConstitutionLoader.swift` does not;
- `TaskScanner.swift` exists and `TaskScanner.swift` does not;
- the source tree does not contain `ConstitutionLoader` as a symbol.

## Verify

Run:

```bash
xcodebuild -scheme MerlinTests \
  -configuration Debug \
  -derivedDataPath build/DerivedData \
  SYMROOT=build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  ENABLE_HARDENED_RUNTIME=NO \
  -only-testing:MerlinTests/SDDArtifactCutoverTests \
  test
```

Expected: tests fail against the pre-migration repository.

## Commit

```bash
git add tasks/task-344a-sdd-artifact-cutover-tests.md MerlinTests/Unit/SDDArtifactCutoverTests.swift
git commit -m "Task 344a — SDD artifact cutover tests"
```
