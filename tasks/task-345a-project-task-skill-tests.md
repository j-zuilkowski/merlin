# Task 345a — Project Task Skill Tests

## Context

The core artifact cutover is complete. The built-in `/project:*` skills must now be
first-class SDD producers and validators, not partially renamed phase-era instructions.

## Behavior

WHEN Merlin exposes project-construction skills THE system SHALL expose `/project:task`
as the command for creating TDD task pairs.

WHEN Merlin scaffolds a project THE system SHALL produce `constitution.md`, `spec.md`,
and `tasks/`.

WHEN Merlin adopts, revises, or releases a project THE system SHALL reference the new
SDD artifact names only.

## Test Scope

Write failing tests in `MerlinTests/Unit/ProjectTaskSkillCutoverTests.swift`.

The tests must assert:

- `Merlin/Skills/Builtin/project-task/SKILL.md` exists;
- `Merlin/Skills/Builtin/project-phase/SKILL.md` does not exist;
- project skill text contains `/project:task`;
- project skill text does not contain `/project:phase`, `project-phase`, `CLAUDE.md`,
  `architecture.md`, `phases/`, or `phase-`;
- `project:init`, `project:adopt`, `project:revise`, and `project:release` use
  `constitution.md`, `spec.md`, `tasks/`, and task vocabulary.

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
  -only-testing:MerlinTests/ProjectTaskSkillCutoverTests \
  test
```

Expected: tests fail until the built-in project skills are fully reconciled.

## Commit

```bash
git add tasks/task-345a-project-task-skill-tests.md MerlinTests/Unit/ProjectTaskSkillCutoverTests.swift
git commit -m "Task 345a — project task skill tests"
```
