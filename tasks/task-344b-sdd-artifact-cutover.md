# Task 344b — SDD Artifact Cutover

## Context

Task 344a added the failing cutover contract. This task implements the hard migration
for root artifacts, historical task-sheet filenames, core Swift symbols, and runtime
configuration vocabulary.

## Behavior

WHEN Merlin loads project instructions THE system SHALL read `constitution.md` from the
project root, `.merlin/constitution.md`, and the user's home directory, in that order.

WHEN Merlin scans implementation history THE system SHALL read `tasks/` and `task-*`
files as the canonical source of declared surfaces.

WHEN CAG is configured THE system SHALL use constitution/task vocabulary for cache
configuration keys and in-memory settings.

## Implementation

- Rename `CLAUDE.md` to `constitution.md`.
- Rename `architecture.md` to `spec.md`.
- Rename `phases/` to `tasks/`.
- Rename tracked historical `phase-*` files to `task-*`.
- Rename `CLAUDEMDLoader` to `ConstitutionLoader`.
- Rename `PhaseScanner` to `TaskScanner`.
- Rename CAG settings from `pin_claude_md` / `pinned_phase_docs` to
  `pin_constitution` / `pinned_task_docs`.

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
  -only-testing:MerlinTests/SDDArtifactCutoverTests \
  test
```

Expected: `SDDArtifactCutoverTests` pass.

## Commit

```bash
git add constitution.md spec.md tasks Merlin MerlinTests TestHelpers MerlinDisciplineCLI project.yml
git commit -m "Task 344b — SDD artifact cutover"
```
