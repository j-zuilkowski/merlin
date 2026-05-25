# Phase 343a — CAG Documentation And Status Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 342b complete: CAG foundation, Anthropic prompt-cache support, and cache
metrics are implemented.

Recommended execution model: GPT-5.3-Codex.

This phase closes documentation drift:

- Architecture still contains stale `v2.3 planned` labels for llama.cpp and
  slot status even though they are built.
- The CAG section currently says "not implemented" and "planned" even after
  phases 341/342 land.
- User/developer docs need a concise CAG description and settings surface.

TDD coverage:
  File 1 - `MerlinTests/Unit/ArchitectureStatusLabelTests.swift`:
    `testArchitectureDoesNotMarkV23BuiltFeaturesAsPlanned`
    `testArchitectureMarksCAGAsBuilt`
    `testArchitectureCAGSectionDoesNotSayNotImplemented`
    `testArchitectureMentionsCAGRuntimeFiles`

  File 2 - extend `MerlinTests/Unit/DocumentationSweepTests.swift`:
    `testReleaseDocsMentionCAG`
    `testReleaseDocsDoNotCallCAGPlanned`

---

## Write to: MerlinTests/Unit/ArchitectureStatusLabelTests.swift

Read `architecture.md` from the repo root.

Assertions:

- It must not contain `v2.3 planned`.
- It must contain `## llama.cpp First-Class Local Provider [v2.3]`.
- It must contain `## CAG — Cache-Augmented Generation [v11]`.
- The CAG section must not contain `not implemented`, `planned`, or
  `phase work is deferred`.
- The CAG section must mention:
  - `Merlin/CAG/CachePolicy.swift`
  - `Merlin/CAG/CacheMetrics.swift`
  - `CompletionRequest.cachePolicy`
  - `AnthropicProvider`
  - `cache_control`

Scope the "planned" assertion to the CAG section so unrelated future roadmap
content is not over-constrained.

## Edit: MerlinTests/Unit/DocumentationSweepTests.swift

Release-current docs to scan:

- `FEATURES.md`
- `Merlin/Docs/UserGuide.md`
- `Merlin/Docs/DeveloperManual.md`

Assertions:

- These docs mention CAG or Cache-Augmented Generation.
- They do not call CAG "planned" or "not implemented".
- They mention that Anthropic uses explicit prompt-cache markers and other
  providers rely on stable prefix bytes/automatic cache behavior.

## Verify
```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```
Expected: BUILD FAILED with architecture/documentation assertions naming stale
labels and missing CAG docs.

## Commit
```bash
git add MerlinTests/Unit/ArchitectureStatusLabelTests.swift \
        MerlinTests/Unit/DocumentationSweepTests.swift \
        phases/phase-343a-cag-docs-status-tests.md
git commit -m "Phase 343a — CAG docs and status tests (failing)"
```
