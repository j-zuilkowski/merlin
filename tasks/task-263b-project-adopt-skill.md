# Task 263b — project:adopt Skill

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 263a complete: failing tests asserting project:adopt SKILL.md exists.

The first adoption target is Merlin itself — this skill must handle the case where task
files already exist and conventions are already partially documented.

---

## Write to

### ~/.merlin/skills/project-adopt/SKILL.md

```bash
mkdir -p ~/.merlin/skills/project-adopt
```

File content:

```markdown
# project:adopt

Apply Merlin v2.2 Project Discipline to an existing project. Different from `/project:init`
because the project already exists with its own conventions and history.

## Trigger

User says any of:
- "adopt this project"
- "apply discipline to [project]"
- "add Merlin discipline to existing project"
- "/project:adopt"
- "bring [project] under discipline"

## Steps

1. **Detect language and adapter**:
   - Check for `project.yml` → Swift/Xcode adapter.
   - Check for `Cargo.toml` → Rust/Cargo adapter.
   - Check for `package.json` → TypeScript/Node adapter (future).
   - If ambiguous, ask the user to choose.

2. **Read existing documentation** (`constitution.md`, `AGENTS.md`, `spec.md`):
   - Preserve all existing content.
   - If a "Project Discipline" section is absent, append one describing the v2.2 subsystem.
   - Never rewrite an existing constitution.md from scratch.

3. **Scan current codebase state**:
   a. Run `TaskScanner.scan(projectPath:)` — report drift (green/yellow/red/orange).
   b. Run `ManualCoverageScanner.scan(projectPath:adapter:)` — count uncovered surfaces.
   c. Run `WhyCommentScanner.scan(projectPath:adapter:)` — count trigger violations.
   d. Run `ProseReadabilityChecker` on each doc file — report grade violations.

4. **Write `.merlin/project.toml`**:
   - Set `adapter` to the detected adapter key.
   - Set `manual_coverage_baseline` = current uncovered-surface count from step 3b.
   - Set `decay_per_release` = 10 (default; user can override).
   - Set `discipline_layers` = ["soft_prompt", "pre_commit"].

5. **Install git hooks** (confirm per layer):
   - Layer 2 (soft prompts): always recommended.
   - Layer 3 (pre-commit): confirm before installing — existing hooks are preserved.
   - Call `GitHookInstaller.install(projectPath:)`.

6. **Seed adapters**: Call `AdapterRegistry.installSeedAdapters(into:)` if
   `~/.merlin/adapters/` does not exist.

7. **Install Vale styles**: Call `ValeStyleWriter.writeStyles(to:)` for
   `~/.merlin/styles/`.

8. **Write adoption report** (one page, plain language):
   ```
   Adopted. Language: Swift (swift-xcode adapter).
   Baseline coverage gap: 314 surfaces.
   Default decay: 10 per release → comprehensive in 32 releases.
   WHY-comment violations found: 47.
   Prose readability fails in 6 docs.
   Task drift: green except 3 yellow.
   Next step: /project:revise to start working through the backlog.
   ```

9. **Commit** (after confirmation): `git commit -m "Adopt Merlin v2.2 discipline"`.

## First adoption target: Merlin itself

When run against `~/Documents/localProject/merlin`:
- Adapter: `swift-xcode`
- Expected baseline gap: non-zero (many existing surfaces, partially documented)
- Task drift: mostly green (230+  tasks, well-maintained)
- WHY-comment violations: present in engine files (Task.sleep, try?)
- Prose readability: spec.md targets grade 11; user-manual.md targets grade 9

## Output

- `.merlin/project.toml` written with detected language, baseline, and decay.
- Git hooks installed (Layer 2 and 3 if opted in).
- `constitution.md` updated with "Project Discipline" section if absent.
- Adoption report shown to user.
- Single commit.

## Constraints

- Never delete or overwrite existing content in `constitution.md`.
- Never install hooks without user confirmation.
- If `.merlin/project.toml` already exists, ask whether to overwrite or merge.
- `manual_coverage_baseline` is the most critical field — setting it too low creates
  immediate block; too high delays closure. Default to the actual scan count.
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

Expected: **BUILD SUCCEEDED** and all task 263a `ProjectAdoptSkillTests` pass.

## Commit

```bash
git add tasks/task-263b-project-adopt-skill.md
git commit -m "Task 263b — project:adopt skill (SKILL.md) — first target: Merlin itself"
```
