# Phase 259b — project:init Skill

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 259a complete: failing tests asserting the project:init SKILL.md exists.

Skill files are Markdown documents in `~/.merlin/skills/<skill-name>/SKILL.md`.
No Swift code is written in this phase — only the skill file.

---

## Write to

### ~/.merlin/skills/project-init/SKILL.md

```bash
mkdir -p ~/.merlin/skills/project-init
```

File content:

```markdown
# project:init

Scaffold a new project with full Merlin v2.2 Project Discipline Subsystem support.

## Trigger

User says any of:
- "init a new project"
- "scaffold a new [language] project"
- "create a project with Merlin discipline"
- "/project:init"

## Steps

1. **Ask for project metadata** (do not assume defaults):
   - Project name and one-line description
   - Language — present supported options: `swift`, `rust`
   - License (MIT / Apache-2.0 / proprietary)
   - Doc-set choice: `full` (all seven docs) or `minimal` (README + CLAUDE.md only)
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

6. **Write doc set** from `~/.merlin/templates/docs/`:
   - Full: README.md, architecture.md, api.md, developer-guide.md, user-manual.md,
     FEATURES.md, CHANGELOG.md
   - Minimal: README.md

7. **Write `phases/` directory** with `phase-00-scaffold.md` documenting the initial state.

8. **Install git hooks** (if Layer 3 opted in):
   Call `GitHookInstaller.install(projectPath:)` — writes `post-commit` and `pre-push`.

9. **Write `.claude/settings.json`** with Stop, SessionStart, UserPromptSubmit hooks
   pointing at `DisciplineEngine`.

10. **Write `.vale.ini`** pointing at `~/.merlin/styles/`:
    ```ini
    StylesPath = ~/.merlin/styles
    MinAlertLevel = warning
    [*.md]
    BasedOnStyles = Merlin
    ```
    Call `ValeStyleWriter.writeStyles(to:)` to install the Merlin style folder.

11. **Run `AdapterRegistry.installSeedAdapters(into:)`** if
    `~/.merlin/adapters/` does not yet exist.

12. **Initial git commit**: `git add -A && git commit -m "Phase 00 — scaffold"`

13. **Report to user**: project path, adapter chosen, baseline coverage gap (0 for new
    project), installed hooks, next step (`/project:phase` to start TDD).

## Output

- A runnable project scaffold at the chosen path.
- `.merlin/project.toml` with adapter selection and zero baseline.
- Git hooks installed (if opted in).
- Doc set present (full or minimal).
- `phases/phase-00-scaffold.md` committed.

## Constraints

- Never run `git push` — only local commit.
- Never overwrite an existing `CLAUDE.md` — append a "Project Discipline" section if absent.
- If the project path already exists and is non-empty, abort and suggest `/project:adopt`.
- Adapter selection is the only irreversible decision. Confirm before proceeding.
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all phase 259a `ProjectInitSkillTests` pass.

## Commit

```bash
git add phases/phase-259b-project-init-skill.md
git commit -m "Phase 259b — project:init skill (SKILL.md)"
```

Note: The SKILL.md is written to `~/.merlin/skills/project-init/SKILL.md` on the developer's
machine. Codex must create the directory and write the file as a shell step before running the
test suite.
