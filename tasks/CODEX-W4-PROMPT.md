# Single-Shot Codex Prompt — W4 Trace-Audit Phases 320–321

Source: `merlin-eval/TRACE-AUDIT.md` (W4 trace-the-calls audit).
Two TDD pairs: 320 wires `WorkerDiffView`'s dead toolbar buttons; 321 fixes a
`DocReferenceGraph` comment-parsing false positive.

Paste the block below verbatim as the Codex task prompt.

---

```
You are executing trace-audit fix phases for the Merlin macOS SwiftUI app.
Working directory: ~/Documents/localProject/merlin

Rules (non-negotiable):
- Swift 5.10, macOS 14+, SWIFT_STRICT_CONCURRENCY=complete
- Zero warnings, zero errors after every NNb phase
- TDD: phase NNa writes failing tests, NNb makes them pass — commit after EACH phase
- Never use git add -A; add only the specific files named in the phase's Commit step
- Never skip a commit; never amend a prior commit; never push
- The task files in tasks/ are self-contained — each has the exact file contents
  to write, the exact Verify command, and the exact Commit command. Follow them
  literally. Do not improvise file contents or commands.

Execute the following four phases STRICTLY IN ORDER. For each phase:
  1. Read the task file from tasks/
  2. Write/edit exactly the files in that phase's "Write to:" / "Edit:" section
  3. Run `xcodegen generate` (a new MerlinTests file must be added to the project)
  4. Run the phase's Verify command and CONFIRM the expected result before continuing
  5. Run the phase's Commit command
If a Verify result does not match Expected, STOP and report — do not proceed.

---

PHASE 320a — Read tasks/task-320a-worker-diff-actions-tests.md
Write: MerlinTests/Unit/WorkerDiffViewActionTests.swift
Kind: COMPILE-FAILURE phase — verify with build-for-testing.
Expected: BUILD FAILED, with errors naming `rejectAllChanges` and
  `acceptAndMergeChanges` as missing members of `WorkerDiffView`.
Commit: git add MerlinTests/Unit/WorkerDiffViewActionTests.swift tasks/task-320a-worker-diff-actions-tests.md
        git commit -m "Phase 320a — WorkerDiffViewActionTests (failing)"

PHASE 320b — Read tasks/task-320b-worker-diff-actions.md
Edit: Merlin/UI/Sidebar/WorkerDiffView.swift  (wire the two empty-action toolbar
  buttons; add the `rejectAllChanges()` and `acceptAndMergeChanges()` methods)
Kind: IMPLEMENTATION phase — verify with test, then build-for-testing on BOTH
  the MerlinTests and MerlinTests-Live schemes.
Expected: both WorkerDiffViewActionTests pass; BUILD SUCCEEDED on both schemes,
  zero warnings.
Commit: git add Merlin/UI/Sidebar/WorkerDiffView.swift tasks/task-320b-worker-diff-actions.md
        git commit -m "Phase 320b — Wire WorkerDiffView reject-all / accept-and-merge"

PHASE 321a — Read tasks/task-321a-doc-reference-comment-tests.md
Write: MerlinTests/Unit/DocReferenceGraphCommentTests.swift
Kind: RUNTIME-FAILURE phase — verify with test (build succeeds, the test fails).
Expected: BUILD SUCCEEDED; testWordsInsideCaseLineCommentsAreNotFlagged FAILS
  against today's scanner.
Commit: git add MerlinTests/Unit/DocReferenceGraphCommentTests.swift tasks/task-321a-doc-reference-comment-tests.md
        git commit -m "Phase 321a — DocReferenceGraphCommentTests (failing)"

PHASE 321b — Read tasks/task-321b-doc-reference-comment.md
Edit:    Merlin/Discipline/DocReferenceGraph.swift  (§1 — replace the whole
         `extractEnumCaseNames(from:)` method)
Rewrite: MerlinTests/Unit/DocReferenceDanglingTests.swift  (§2 — onto fenced-block
         fixtures; repairs test rot left by phase 319b)
Kind: IMPLEMENTATION phase — verify with test (all seven DocReference* classes),
  then build-for-testing.
Expected: every test in all seven DocReference* classes passes; BUILD SUCCEEDED,
  zero warnings.
Commit: git add Merlin/Discipline/DocReferenceGraph.swift MerlinTests/Unit/DocReferenceDanglingTests.swift tasks/task-321b-doc-reference-comment.md
        git commit -m "Phase 321b — DocReferenceGraph extractEnumCaseNames strips // comments"

---

After 321b, report: four commits made, and the output of
  git log --oneline -4
Do not push.
```

---

## Post-run verification (run yourself after Codex finishes)

```bash
xcodebuild -scheme merlin-discipline build -derivedDataPath /tmp/merlin-derived \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -2
/tmp/merlin-derived/Build/Products/Debug/merlin-discipline scan ~/Documents/localProject/merlin \
  | grep -E 'finding|stubbedImplementation|docStaleReference'
```
Expected after 320b + 321b land: the 2 `stubbedImplementation` findings (WorkerDiffView)
clear, and the 2 remaining `docStaleReference` findings (`shape`, `signature`) clear —
total drops 218 → ~214.
