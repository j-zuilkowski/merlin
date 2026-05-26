# Task 345b — Project Task Skill

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Context

Task 345a added the project-skill cutover tests. This task reconciles the bundled
`/project:*` skills with the SDD artifact names and command vocabulary.

## Behavior

WHEN the user asks Merlin to create a TDD work unit THE system SHALL use `/project:task`
and write `tasks/task-NNa-*` plus `tasks/task-NNb-*`.

WHEN Merlin scaffolds, adopts, revises, or releases a project THE system SHALL use
`constitution.md`, `spec.md`, and `tasks/` as canonical artifacts.

## Implementation

- Reconciled `project-task/SKILL.md` to use `# project:task`, `/project:task`, task
  numbering, and `New surface introduced in task NNb:`.
- Reconciled `project:init` scaffold commit and next-step text.
- Reconciled `project:revise` drift instructions and examples.
- Reconciled `project:release` gate section names and added an explicit SDD artifact
  pre-flight check.

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
  -only-testing:MerlinTests/ProjectTaskSkillCutoverTests \
  test
```

Expected: `ProjectTaskSkillCutoverTests` pass.

## Commit

```bash
git add Merlin/Skills/Builtin/project-task/SKILL.md \
        Merlin/Skills/Builtin/project-init/SKILL.md \
        Merlin/Skills/Builtin/project-revise/SKILL.md \
        Merlin/Skills/Builtin/project-release/SKILL.md \
        tasks/task-345b-project-task-skill.md
git commit -m "Task 345b — project task skill"
```
