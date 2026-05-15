# Phase 281 — Bundle Built-in Skills into the App

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
v2.2.2 released.

This is a **shipping-bug fix** (single phase file — no NNa/NNb pair).

### The bug

`AppState.installBuiltinSkills()` copies skill folders from `Bundle.main/Builtin` to
`~/.merlin/skills/` at launch. But `project.yml` **excludes** `Skills/Builtin/**` from
the Merlin target's sources and declares no resource for it, so the folder is **never
bundled into the app**. Verified: a freshly built `Merlin.app` has no
`Contents/Resources/Builtin/`.

`installBuiltinSkills()` has a `#filePath`-based fallback (`builtinSkillsSourceURL()`)
that resolves to the repo's `Merlin/Skills/Builtin` — so it only works on the machine
where the app was compiled. A DMG installed on any other Mac installs **zero skills**:
not the 8 built-ins (`commit`, `debug`, `explain`, `plan`, `refactor`, `review`,
`summarise`, `test`), and not the 5 v2.2 `project:*` skills (`init`, `phase`, `revise`,
`release`, `adopt`) — which were not in `Builtin/` at all.

### The fix

1. The 5 `project:*` skill folders are added to `Merlin/Skills/Builtin/`, each as
   `project-<name>/SKILL.md`, matching the existing built-in skill layout. They are now
   version-controlled instead of living only in `~/.merlin/` and in phase files
   259b–263b.
2. `project.yml` adds `Merlin/Skills/Builtin` as a **folder reference**
   (`type: folder`) on the Merlin target, so it is copied into the app bundle as
   `Merlin.app/Contents/Resources/Builtin/`. The `excludes: Skills/Builtin/**` line
   stays — the folder reference is the single, intentional way the directory enters the
   bundle.

After this, `installBuiltinSkills()` resolves `Bundle.main/Builtin` for real and copies
all 13 skill folders to `~/.merlin/skills/` on first launch — on any machine.

---

## Edit

- `Merlin/Skills/Builtin/project-init/SKILL.md`, `project-phase/SKILL.md`,
  `project-revise/SKILL.md`, `project-release/SKILL.md`, `project-adopt/SKILL.md` —
  the five `project:*` skill files (content from phases 259b–263b).
- `project.yml` — Merlin target `sources`: add

  ```yaml
      - path: Merlin/Skills/Builtin
        type: folder
  ```

- Run `xcodegen generate` — `project.pbxproj` gains `Builtin` as a `folder`
  `PBXFileReference` in the Merlin target's Resources build phase.

No Swift changes — `installBuiltinSkills()` is already correct; it was only ever missing
its input.

---

## Verify

```bash
xcodegen generate

xcodebuild -scheme Merlin build \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    SYMROOT=build \
    CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES \
    ENABLE_HARDENED_RUNTIME=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

ls build/Release/Merlin.app/Contents/Resources/Builtin/
```

Expected: **BUILD SUCCEEDED**, and `Contents/Resources/Builtin/` lists all **13** skill
folders (8 built-ins + 5 `project-*`). Before this phase that directory does not exist.

## Commit

```bash
git add phases/phase-281-bundle-builtin-skills.md \
    project.yml \
    Merlin.xcodeproj/project.pbxproj \
    Merlin/Skills/Builtin/project-init/SKILL.md \
    Merlin/Skills/Builtin/project-phase/SKILL.md \
    Merlin/Skills/Builtin/project-revise/SKILL.md \
    Merlin/Skills/Builtin/project-release/SKILL.md \
    Merlin/Skills/Builtin/project-adopt/SKILL.md
git commit -m "Phase 281 — Bundle Builtin/ skills into the app (fixes skill install)"
```

## Fixes

`Merlin/Skills/Builtin/` is now bundled into the app as a folder resource, so
`installBuiltinSkills()` works from a real install, not just the build machine. The 5
`project:*` skills are added to `Builtin/` and are now version-controlled.

Ships in the next release (v2.2.3).

## Follow-up (not in this phase)

The `Project*SkillTests` suites assert `~/.merlin/skills/project-*/SKILL.md` and are
gated behind `RUN_LIVE_TESTS` (phase 279). They could now instead verify the bundled
copy (`Bundle/Builtin/project-*/SKILL.md`) and be un-gated — a separate test-quality
improvement.
