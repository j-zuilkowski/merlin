# Task 301 — versionBumpCandidate Cleanup

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Cleanup unit of the wiring plan. Tasks 294–300 complete.

`FindingCategory.versionBumpCandidate` is defined in `Merlin/Discipline/Finding.swift`
but is produced nowhere — no scanner, gate, or generator emits it. Unlike
`overrideAuditAccumulation` (now produced by `OverrideAuditLog`), there is no component
that owns "this change warrants a version bump", and inventing one is out of scope for
the wiring plan.

Decision: **delete the unused case.** A version-bump detector, if wanted, is a separate
feature with its own task pair — not a dangling enum case.

## Edit — remove all three `versionBumpCandidate` references
`versionBumpCandidate` is referenced in three places. Remove it from ALL of them, or the
test target fails to compile and the Verify grep still matches:

1. `Merlin/Discipline/Finding.swift` — remove `case versionBumpCandidate` from
   `enum FindingCategory`.
2. `MerlinTests/Unit/FindingModelTests.swift` — delete the single line
   `XCTAssertEqual(FindingCategory.versionBumpCandidate.rawValue, "versionBumpCandidate")`
   (one of a series of per-case rawValue assertions; leave the other category
   assertions in that test untouched).
3. `Merlin/Docs/DeveloperManual.md` — in the `FindingCategory` cases comment, drop
   `versionBumpCandidate` from the list (markdown only, not build-blocking, but the
   Verify grep checks it).

## Verify
- `grep -rn 'versionBumpCandidate' Merlin MerlinTests` returns nothing.
- Full build succeeds — confirm no `switch` over `FindingCategory` relied on the case
  (the enum is consumed mostly via `.rawValue`; fix any exhaustive switch if the compiler
  flags one):
```
xcodegen generate
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: BUILD SUCCEEDED, zero warnings.

Then run the full suite to confirm no regression:
```
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
```

## Commit
```
git add Merlin/Discipline/Finding.swift MerlinTests/Unit/FindingModelTests.swift \
  Merlin/Docs/DeveloperManual.md tasks/task-301-version-bump-candidate-cleanup.md
git commit -m "Task 301 — Remove unused versionBumpCandidate finding category"
```
