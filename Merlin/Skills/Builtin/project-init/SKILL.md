# project:init

Scaffold a new project with full Merlin v2.2 Project Discipline Subsystem support.

## The discipline pipeline

Every project Merlin manages flows through four artifacts, upstream to downstream:

    vision.md  →  architecture.md  →  phases/  →  code
     (intent)      (committed design)  (specs)     (implementation)

`vision.md` is the launchpad — every new idea is captured there first, then promoted to
`architecture.md` once it is a committed design decision, broken into TDD phase files,
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
   - Doc-set choice: `full` (all docs) or `minimal` (README + CLAUDE.md + vision.md)
   - Discipline Layer 2 (soft prompts)? Default yes.
   - Discipline Layer 3 (pre-commit hooks)? Default yes.

2. **Select adapter**: Map the chosen language to the matching adapter key
   (`swift` → `swift-xcode`, `rust` → `rust-cargo`). Confirm with the user.

3. **Scaffold via language-native tooling**:
   - Swift: `xcodegen generate` after writing `project.yml`
   - Rust: `cargo new <name>`
   - Do NOT reinvent the toolchain's scaffolding.

4. **Write `.merlin/project.toml`** using `ProjectConfigLoader.defaultConfig(adapter:)`.

5. **Write `CLAUDE.md`** from `~/.merlin/templates/docs/CLAUDE.md.template`,
   substituting `{project_name}`, `{language}`, `{adapter}`.

6. **Write `vision.md`** — the idea launchpad. Two sections:
   - `## Active` — seed it with the Initial vision paragraph from step 1 as the first
     entry. These are ideas awaiting promotion to `architecture.md`.
   - `## Deferred` — a placeholder line for now. Ideas consciously parked later, each
     with a "reconsider when".
   `vision.md` is written for **both** doc-set tiers — it is the launchpad, so even a
   minimal project gets it.

7. **Write doc set** from `~/.merlin/templates/docs/`:
   - Full: README.md, architecture.md, api.md, developer-guide.md, user-manual.md,
     FEATURES.md, CHANGELOG.md
   - Minimal: README.md
   (`CLAUDE.md` from step 5 and `vision.md` from step 6 are written in both tiers.)

8. **Write `phases/` directory** with `phase-00-scaffold.md` documenting the initial state.

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

13. **Initial git commit**: `git add -A && git commit -m "Phase 00 — scaffold"`

14. **Report to user**: project path, adapter chosen, baseline coverage gap (0 for new
    project), installed hooks, doc set, `vision.md` seeded with the founding idea, next
    step (`/project:phase` to start TDD, or `/project:revise` to grow the vision).

## Output

- A runnable project scaffold at the chosen path.
- `vision.md` with the founding idea in `## Active` and an empty `## Deferred`.
- `.merlin/project.toml` with adapter selection and zero baseline.
- Git hooks installed (if opted in).
- Doc set present (full or minimal); `vision.md` present in either tier.
- `phases/phase-00-scaffold.md` committed.

## Constraints

- Never run `git push` — only local commit.
- Never overwrite an existing `CLAUDE.md` — append a "Project Discipline" section if absent.
- Never overwrite an existing `vision.md` — if present, leave it untouched.
- If the project path already exists and is non-empty, abort and suggest `/project:adopt`.
- Adapter selection is the only irreversible decision. Confirm before proceeding.
