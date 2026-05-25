# Codex Orchestration Prompt — Merlin v2.2.0 (Project Discipline Subsystem)

Paste the block below into Codex as the first message.

---

```
v2.1.0 is tagged and released. HEAD is on main. Working dir: ~/Documents/localProject/merlin.

Read constitution.md and spec.md first (search for "## V2.2 — Project Discipline Subsystem").
Then execute these phases in strict order, committing after each one:

  241a → 241b → 242a → 242b → 243a → 243b → 244a → 244b → 245a → 245b →
  246a → 246b → 247a → 247b → 248a → 248b → 249a → 249b → 250a → 250b →
  251a → 251b → 252a → 252b → 253a → 253b → 254a → 254b → 255a → 255b →
  256a → 256b → 257a → 257b → 258a → 258b → 259a → 259b → 260a → 260b →
  261a → 261b → 262a → 262b → 263a → 263b → 264a → 264b → 265a → 265b

Rules:
- TDD: every NNa ends with BUILD FAILED + commit. Every NNb ends with BUILD SUCCEEDED +
  passing tests + commit. Never batch commits. Never git add -A. Never --no-verify.
- CODE SIGNING: this sandbox has no signing cert. Every xcodebuild call must include:
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  The task files already include these flags. Do not remove them.
- Per-phase loop: cat the task file → implement → verify (expected outcome is in the file)
  → commit → next phase.
- Stop and report if: verify outcome doesn't match expectation, any pre-existing test
  regresses, git commit is rejected, or a surface named in a later phase already exists.
- New source files go in Merlin/Discipline/ (new subdirectory for v2.2 types).
- Skill SKILL.md files go in ~/.merlin/skills/project-<name>/SKILL.md.

Begin:

cd ~/Documents/localProject/merlin
git diff --quiet && git diff --cached --quiet && echo "clean" || echo "dirty"
cat tasks/task-241a-adapter-registry-tests.md
```
