# Merlin v2.2.3 — Built-in Skill Installation Fix

Released: 2026-05-15

## Summary

v2.2.3 fixes built-in skill installation. The `Merlin/Skills/Builtin/` directory is now
bundled inside the app, so a fresh install ships every skill and installs them to
`~/.merlin/skills/` on first launch — on any machine, not just the machine the app was
built on.

## What's new

- All 13 built-in skills now ship inside the app bundle: the 8 core skills (`commit`,
  `debug`, `explain`, `plan`, `refactor`, `review`, `summarise`, `test`) and the 5
  `project:*` discipline skills (`project:init`, `project:task`, `project:revise`,
  `project:release`, `project:adopt`).
- `installBuiltinSkills()` copies any missing skill to `~/.merlin/skills/` at launch;
  skills already present — including ones you have customised — are left untouched.

## Internal changes

- `project.yml` adds `Merlin/Skills/Builtin` as a folder-reference resource on the
  Merlin target, so the directory is copied into `Merlin.app/Contents/Resources/Builtin/`.
  Previously the directory was excluded from the target and never bundled —
  `installBuiltinSkills()` only resolved its input via a build-machine `#filePath`
  fallback, so a distributed build installed no skills at all.
- The 5 `project:*` `SKILL.md` files are now version-controlled in
  `Merlin/Skills/Builtin/` rather than living only in `~/.merlin/` and in task files.

## Migration

- No user data migration required. `installBuiltinSkills()` skips any skill folder that
  already exists in `~/.merlin/skills/`, so existing and customised skills are preserved.
