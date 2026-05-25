# Codex Orchestration Prompt — Merlin v2.2.1 (Project Discipline Remediation)

Paste the block below into Codex as the first message.

---

```
v2.2.0 is committed (HEAD: ecbae6f, tag v2.2.0 local). Working dir: ~/Documents/localProject/merlin.

This is a remediation series — it fixes bugs found in a code review of the v2.2 Project
Discipline Subsystem. Read constitution.md first. Then execute these phases in strict order,
committing after each one, without stopping between phases:

  266a → 266b → 267a → 267b → 268a → 268b → 269a → 269b →
  270a → 270b → 271a → 271b → 272a → 272b → 273a → 273b

Rules:
- TDD: every NNa ends with a commit of just the failing tests. Every NNb ends with
  BUILD SUCCEEDED + passing tests + commit. Never batch commits. Never git add -A.
  Never --no-verify.
- NNa expected outcome VARIES per phase — each task file states its own expectation in
  the ## Verify section. Some NNa phases are BUILD FAILED (new symbol referenced); others
  are BUILD SUCCEEDED with the new tests FAILING at runtime (the bug is a behaviour bug in
  an existing symbol). Trust the task file's stated expectation, not a blanket rule.
- CODE SIGNING: this sandbox has no signing cert. Every xcodebuild call must include:
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
  The task files already include these flags. Do not remove them.
- Per-phase loop: cat the task file → implement → verify against the file's stated
  expectation → commit → next phase.
- Some phases update pre-existing tests (269b updates AdapterSeedTests). The task file
  names those files — that is expected, not a regression.
- Stop and report only if: verify outcome does not match the task file's stated
  expectation, a pre-existing test unrelated to the phase regresses, or a git commit is
  rejected by a hook.
- 273b bumps the version and creates a LOCAL tag only. Do NOT push and do NOT run
  `gh release create` — leave push/release as a manual step for the user.

Begin:

cd ~/Documents/localProject/merlin
git diff --quiet && git diff --cached --quiet && echo "clean" || echo "dirty"
cat tasks/task-266a-finding-dedup-key-tests.md
```
