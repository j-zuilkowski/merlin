# project:release

Consolidated release gate: verifies all discipline checks pass, bumps version, tags, and
publishes.

## Trigger

User says any of:
- "release version X.Y.Z"
- "cut a release"
- "publish a new release"
- "/project:release"
- "ship v2.2.0"

## Steps

### Phase 1 — Pre-flight

Run all release gate checks in order. Any failure stops the release and reports the
failing check. The user must fix or dismiss with rationale before re-running.

**Checklist:**

```
□  All phase tests pass (xcodebuild test / cargo test)
□  api.md regenerated (APIDocGenerator.generate called; diff committed if changed)
□  developer-guide.md mechanical sections regenerated (DevGuideGenerator.generate)
□  user-manual.md: zero new uncovered surfaces (ManualCoverageScanner.scan)
□  Manual baseline reduced by ≥ decayPerRelease (ManualBaselineManager.releaseGateCheck)
□  DocReferenceGraph: no red findings (stale references)
□  WhyCommentScanner: zero violations or all have rationale-not-needed annotation
□  ProseReadabilityChecker: all doc files at or under target grade
□  RELEASE-vX.Y.Z.md present and non-empty
□  CHANGELOG.md updated (section for vX.Y.Z present)
□  PhaseScanner: no red/orange drift findings
□  project.yml / Cargo.toml version field matches intended release version
□  CURRENT_PROJECT_VERSION incremented by 1
```

Emit `discipline.release-gate.start` at the beginning.
Emit `discipline.release-gate.fail` with failing check names on any failure.
Emit `discipline.release-gate.pass` on full pass.

### Phase 2 — Version bump

1. Edit `MARKETING_VERSION` in `project.yml` (Swift) or `version` in `Cargo.toml` (Rust)
   to the intended release version.
2. Increment `CURRENT_PROJECT_VERSION` (Swift only) by 1.
3. For Swift: run `xcodegen generate`.
4. Build and confirm About dialog shows the new version string.
5. Commit: `git commit -m "Bump version to X.Y.Z"`.

### Phase 3 — Tag and publish

6. Tag: `git tag vX.Y.Z`
7. Push: `git push && git push --tags`
8. Create GitHub release:
   ```bash
   gh release create vX.Y.Z \
       --repo <owner>/<repo> \
       --title "vX.Y.Z — <Short description>" \
       --notes-file RELEASE-vX.Y.Z.md \
       --latest
   ```
9. For Rust: `cargo publish` (if the crate is public).

### Phase 4 — Post-release bookkeeping

10. Call `ManualBaselineManager.recordRelease(uncoveredCount:)` with the current count.
11. Archive `.merlin/pending.json` snapshot: copy to `.merlin/pending-vX.Y.Z.json`.
12. Report: version shipped, gate checks that passed, baseline delta.

## Output

- Version-bump commit
- Git tag `vX.Y.Z`
- GitHub release created
- `.merlin/manual-coverage-baseline.json` updated with new snapshot

## Constraints

- Never re-use or move a tag that has already been pushed to the remote.
- Never skip the release gate — there is no force-release option.
- Never push without first tagging.
- Always create the GitHub release immediately after pushing — tags alone do not update
  the "Latest" badge on GitHub.
- `RELEASE-vX.Y.Z.md` must be written by the user before running the skill; the skill
  does not generate it automatically.
