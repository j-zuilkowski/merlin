# Task 288b — Vision Launchpad

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 288a complete: failing tests asserting `project:init` scaffolds and seeds
`vision.md`.

After this task, `vision.md` is the first-class launchpad of the discipline pipeline
— `vision.md → spec.md → tasks/ → code`. `project:init` seeds it with the
project's founding idea; `project:revise` handles later edits and promotion.

No Swift production code — this task edits two bundled skill files, two installed skill
files, and this repo's own `vision.md`.

---

## Edit

### 1. `project:init` skill — add vision.md scaffolding

Replace the contents of **both**:
  - `~/.merlin/skills/project-init/SKILL.md` (installed copy)
  - `Merlin/Skills/Builtin/project-init/SKILL.md` (bundled copy)

with the following. The changes vs. the current file: a new "discipline pipeline"
preamble; step 1 captures an **Initial vision** paragraph; a new step 6 writes
`vision.md`; the doc-set step notes `vision.md` ships in both tiers; the report step
mentions the seeded vision; remaining steps renumbered.

```markdown
# project:init

Scaffold a new project with full Merlin v2.2 Project Discipline Subsystem support.

## The discipline pipeline

Every project Merlin manages flows through four artifacts, upstream to downstream:

    vision.md  →  spec.md  →  tasks/  →  code
     (intent)      (committed design)  (specs)     (implementation)

`vision.md` is the launchpad — every new idea is captured there first, then promoted to
`spec.md` once it is a committed design decision, broken into TDD task files,
and implemented. `project:init` seeds `vision.md` with the project's founding idea;
later ideas are added or promoted with `project:revise`.

## Trigger

User says any of:
- "init a new project"
- "scaffold a new [language] project"
- "create a project with Merlin discipline"
- "/project:init"

## Steps

1. **Ask for project metadata** (do not assume defaults):
   - Project name and one-line description
   - **Initial vision** — a short paragraph: what the project is for, the problem it
     solves, who it is for. This seeds `vision.md`. Ask for it explicitly; do not
     derive it from the one-line description.
   - Language — present supported options: `swift`, `rust`
   - License (MIT / Apache-2.0 / proprietary)
   - Doc-set choice: `full` (all docs) or `minimal` (README + constitution.md + vision.md)
   - Discipline Layer 2 (soft prompts)? Default yes.
   - Discipline Layer 3 (pre-commit hooks)? Default yes.

2. **Select adapter**: Map the chosen language to the matching adapter key
   (`swift` → `swift-xcode`, `rust` → `rust-cargo`). Confirm with the user.

3. **Scaffold via language-native tooling**:
   - Swift: `xcodegen generate` after writing `project.yml`
   - Rust: `cargo new <name>`
   - Do NOT reinvent the toolchain's scaffolding.

4. **Write `.merlin/project.toml`** using `ProjectConfigLoader.defaultConfig(adapter:)`.

5. **Write `constitution.md`** from `~/.merlin/templates/docs/constitution.md.template`,
   substituting `{project_name}`, `{language}`, `{adapter}`.

6. **Write `vision.md`** — the idea launchpad. Two sections:
   - `## Active` — seed it with the Initial vision paragraph from step 1 as the first
     entry. These are ideas awaiting promotion to `spec.md`.
   - `## Deferred` — a placeholder line for now. Ideas consciously parked later, each
     with a "reconsider when".
   `vision.md` is written for **both** doc-set tiers — it is the launchpad, so even a
   minimal project gets it.

7. **Write doc set** from `~/.merlin/templates/docs/`:
   - Full: README.md, spec.md, api.md, developer-guide.md, user-manual.md,
     FEATURES.md, CHANGELOG.md
   - Minimal: README.md
   (`constitution.md` from step 5 and `vision.md` from step 6 are written in both tiers.)

8. **Write `tasks/` directory** with `task-00-scaffold.md` documenting the initial state.

9. **Install git hooks** (if Layer 3 opted in):
   Call `GitHookInstaller.install(projectPath:)` — writes `post-commit` and `pre-push`.

10. **Write `.claude/settings.json`** with Stop, SessionStart, UserPromptSubmit hooks
    pointing at `DisciplineEngine`.

11. **Write `.vale.ini`** pointing at `~/.merlin/styles/`:
    ```ini
    StylesPath = ~/.merlin/styles
    MinAlertLevel = warning
    [*.md]
    BasedOnStyles = Merlin
    ```
    Call `ValeStyleWriter.writeStyles(to:)` to install the Merlin style folder.

12. **Run `AdapterRegistry.installSeedAdapters(into:)`** if
    `~/.merlin/adapters/` does not yet exist.

13. **Initial git commit**: `git add -A && git commit -m "Task 00 — scaffold"`

14. **Report to user**: project path, adapter chosen, baseline coverage gap (0 for new
    project), installed hooks, doc set, `vision.md` seeded with the founding idea, next
    step (`/project:task` to start TDD, or `/project:revise` to grow the vision).

## Output

- A runnable project scaffold at the chosen path.
- `vision.md` with the founding idea in `## Active` and an empty `## Deferred`.
- `.merlin/project.toml` with adapter selection and zero baseline.
- Git hooks installed (if opted in).
- Doc set present (full or minimal); `vision.md` present in either tier.
- `tasks/task-00-scaffold.md` committed.

## Constraints

- Never run `git push` — only local commit.
- Never overwrite an existing `constitution.md` — append a "Project Discipline" section if absent.
- Never overwrite an existing `vision.md` — if present, leave it untouched.
- If the project path already exists and is non-empty, abort and suggest `/project:adopt`.
- Adapter selection is the only irreversible decision. Confirm before proceeding.
```

### 2. `project:revise` skill — note vision.md as revisable

In **both** `~/.merlin/skills/project-revise/SKILL.md` and
`Merlin/Skills/Builtin/project-revise/SKILL.md`, add a `## Vision` section after
`## Steps`:

```markdown
## Vision

`project:revise` is also how `vision.md` grows after `project:init` seeds it. On request:
- **Add an idea** — append a new entry to `vision.md`'s `## Active` section.
- **Defer an idea** — move an entry from `## Active` to `## Deferred`, adding a
  "reconsider when" note.
- **Promote an idea** — move an `## Active` entry into `spec.md` as a committed
  design decision; remove it from `vision.md`. From there it follows the pipeline:
  `spec.md → tasks/ → code`.
Vision edits are committed in the same batch commit as other revision findings.
```

### 3. `project:adopt` skill — incorporate an existing vision.md

In **both** `~/.merlin/skills/project-adopt/SKILL.md` and
`Merlin/Skills/Builtin/project-adopt/SKILL.md`, insert a new step immediately after the
existing step 2 ("Read existing documentation"), and renumber the subsequent steps
(old 3–9 become 4–10):

```markdown
3. **Incorporate `vision.md`** — the idea launchpad:
   - If the project already has a `vision.md`: preserve it. Ensure it has `## Active`
     and `## Deferred` sections; if it predates the launchpad model, restructure it
     non-destructively — existing content kept verbatim, only re-nested under the right
     section. Never discard or reword existing vision content.
   - If the project has no `vision.md`: create the launchpad scaffold — a `## Active`
     section and a `## Deferred` section. Seed `## Active` from any forward-looking
     content already in the existing docs (an "out of scope", "future work", "roadmap",
     or "TODO" section in `spec.md` / `README.md`); if there is none, leave a
     placeholder line. Do not fabricate a backlog.
   - From here `vision.md` is the project's launchpad: `vision.md → spec.md →
     tasks/ → code`.
```

Also: add a `vision.md` line to the adoption report (step 8, now step 9) — e.g.
`vision.md: incorporated existing (N active ideas)` or `vision.md: launchpad created`
— and add a `vision.md` bullet to the `## Output` section.

### 4. This repo's own `vision.md` — restructure into Active / Deferred

`vision.md` currently opens with a "parking lot for capability ideas" framing and then
lists deferred capabilities directly. Restructure it so it matches the launchpad model
the skill now scaffolds:

- Replace the opening paragraphs with a brief statement that `vision.md` is the idea
  launchpad — ideas land in `## Active`, are promoted to `spec.md`, or are
  parked in `## Deferred`; `spec.md` remains the source of truth for committed
  design.
- Add a top-level `## Active` section. Merlin's recently-captured ideas (the universal
  pre-flight guard, the context-budget resolver, the tool-requirement checker, this
  vision launchpad) have all been promoted to  tasks already — so seed `## Active` with
  a placeholder line: `_No ideas currently awaiting promotion._`
- Add a top-level `## Deferred` section and nest the entire existing body under it:
  the current `## Electronics / KiCad Domain (v2.0)` heading becomes
  `### Electronics / KiCad Domain` under `## Deferred`, and every existing `### ` item
  (EMC, thermal, firmware, mechanical CAD, regulatory, cost-optimized selection) drops
  one heading level to `####`. No deferred content is lost or reworded — only the
  heading hierarchy changes so it sits under `## Deferred`.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**, all task 288a tests pass, no prior task regresses.

**Manual check:** `vision.md` in the repo root opens with the launchpad framing and has
exactly two top-level sections, `## Active` and `## Deferred`, with all prior content
intact under `## Deferred`.

## Commit

```bash
git add tasks/task-288a-vision-launchpad-tests.md \
    tasks/task-288b-vision-launchpad.md \
    Merlin/Skills/Builtin/project-init/SKILL.md \
    Merlin/Skills/Builtin/project-adopt/SKILL.md \
    Merlin/Skills/Builtin/project-revise/SKILL.md \
    vision.md
git commit -m "Task 288b — vision.md launchpad: seed at init, vision→architecture→task→code pipeline"
```

(The installed copies under `~/.merlin/skills/` are outside the repo — update them in
place; they are not part of the commit. Add `MerlinTests/Unit/ProjectVisionLaunchpadTests.swift`
and `Merlin.xcodeproj/project.pbxproj` to the commit if task 288a did not already
commit them.)

## Fixes

The discipline pipeline now has an explicit first artifact. `vision.md` is the idea
launchpad — `project:init` seeds it with the founding idea, `project:adopt` incorporates
an existing `vision.md` (or scaffolds one) when bringing an existing project under
discipline, `project:revise` grows and promotes ideas from it, and the documented flow
is `vision.md → spec.md → tasks/ → code`. This repo's own `vision.md` is
restructured into `## Active` / `## Deferred` to match. Task 259b's `project:init` skill content is superseded by the
version in this task — add a one-line "superseded by task 288b" banner under task
259b's title.
