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

4. **Scan current codebase state**:
   a. Run `TaskScanner.scan(projectPath:)` — report drift (green/yellow/red/orange).
   b. Run `ManualCoverageScanner.scan(projectPath:adapter:)` — count uncovered surfaces.
   c. Run `WhyCommentScanner.scan(projectPath:adapter:)` — count trigger violations.
   d. Run `ProseReadabilityChecker` on each doc file — report grade violations.

5. **Write `.merlin/project.toml`**:
   - Set `adapter` to the detected adapter key.
   - Set `manual_coverage_baseline` = current uncovered-surface count from step 4b.
   - Set `decay_per_release` = 10 (default; user can override).
   - Set `discipline_layers` = ["soft_prompt", "pre_commit"].

6. **Install git hooks** (confirm per layer):
   - Layer 2 (soft prompts): always recommended.
   - Layer 3 (pre-commit): confirm before installing — existing hooks are preserved.
   - Call `GitHookInstaller.install(projectPath:)`.

7. **Seed adapters**: Call `AdapterRegistry.installSeedAdapters(into:)` if
   `~/.merlin/adapters/` does not exist.

8. **Install Vale styles**: Call `ValeStyleWriter.writeStyles(to:)` for
   `~/.merlin/styles/`.

9. **Write adoption report** (one page, plain language):
   ```
   Adopted. Language: Swift (swift-xcode adapter).
   Baseline coverage gap: 314 surfaces.
   Default decay: 10 per release → comprehensive in 32 releases.
   vision.md: incorporated existing (N active ideas) or launchpad created.
   WHY-comment violations found: 47.
   Prose readability fails in 6 docs.
   Task drift: green except 3 yellow.
   Next step: /project:revise to start working through the backlog.
   ```

10. **Commit** (after confirmation): `git commit -m "Adopt Merlin v2.2 discipline"`.

## First adoption target: Merlin itself

When run against `~/Documents/localProject/merlin`:
- Adapter: `swift-xcode`
- Expected baseline gap: non-zero (many existing surfaces, partially documented)
- Task drift: mostly green (230+  tasks, well-maintained)
- WHY-comment violations: present in engine files (Task.sleep, try?)
- Prose readability: spec.md targets grade 11; user-manual.md targets grade 9

## Output

- `.merlin/project.toml` written with detected language, baseline, and decay.
- `vision.md` incorporated or launchpad scaffold created.
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
