# Merlin v2.0 KiCad — Safe Batch Execution Prompts

Do not run phases 209-218 in one Merlin turn. Run one A/B pair per prompt. Start a new turn, or compact context, between pairs.

---

## Batch 209

```text
Read and execute these phase files in order:

1. phases/phase-209a-kicad-mcp-tooling-tests.md
2. phases/phase-209b-kicad-mcp-tooling.md

Follow AGENTS.md exactly. Commit after 209a, then commit after 209b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 210

```text
Read and execute these phase files in order:

1. phases/phase-210a-kicad-artifact-schemas-tests.md
2. phases/phase-210b-kicad-artifact-schemas.md

Follow AGENTS.md exactly. Commit after 210a, then commit after 210b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 211

```text
Read and execute these phase files in order:

1. phases/phase-211a-kicad-schematic-parser-tests.md
2. phases/phase-211b-kicad-schematic-parser.md

Follow AGENTS.md exactly. Commit after 211a, then commit after 211b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 212

```text
Read and execute these phase files in order:

1. phases/phase-212a-schematic-extraction-policy-tests.md
2. phases/phase-212b-schematic-extraction-policy.md

Follow AGENTS.md exactly. Commit after 212a, then commit after 212b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 213

```text
Read and execute these phase files in order:

1. phases/phase-213a-components-footprints-bom-tests.md
2. phases/phase-213b-components-footprints-bom.md

Follow AGENTS.md exactly. Commit after 213a, then commit after 213b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 214

```text
Read and execute these phase files in order:

1. phases/phase-214a-board-routing-policy-tests.md
2. phases/phase-214b-board-routing-policy.md

Follow AGENTS.md exactly. Commit after 214a, then commit after 214b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 215

```text
Read and execute these phase files in order:

1. phases/phase-215a-verification-fab-policy-tests.md
2. phases/phase-215b-verification-fab-policy.md

Follow AGENTS.md exactly. Commit after 215a, then commit after 215b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 216

```text
Read and execute these phase files in order:

1. phases/phase-216a-vendor-order-approval-tests.md
2. phases/phase-216b-vendor-order-approval.md

Follow AGENTS.md exactly. Commit after 216a, then commit after 216b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 217

```text
Read and execute these phase files in order:

1. phases/phase-217a-kicad-workflow-orchestration-tests.md
2. phases/phase-217b-kicad-workflow-orchestration.md

Follow AGENTS.md exactly. Commit after 217a, then commit after 217b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 218

```text
Read and execute these phase files in order:

1. phases/phase-218a-merlin-v2-version-release-tests.md
2. phases/phase-218b-merlin-v2-version-release.md

Follow AGENTS.md exactly. Commit after 218a, then commit after 218b. Do not batch commits. Run the verification command in each phase. If signing blocks xcodebuild, rerun with signing disabled and record it. Only create tag v2.0.0 after 218b tests pass and the 218b commit succeeds.
```
