# Merlin v2.0 KiCad — Safe Batch Execution Prompts

Do not run  tasks 209-218 in one Merlin turn. Run one A/B pair per prompt. Start a new turn, or compact context, between pairs.

---

## Batch 209

```text
Read and execute these task files in order:

1. tasks/task-209a-kicad-mcp-tooling-tests.md
2. tasks/task-209b-kicad-mcp-tooling.md

Follow AGENTS.md exactly. Commit after 209a, then commit after 209b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 210

```text
Read and execute these task files in order:

1. tasks/task-210a-kicad-artifact-schemas-tests.md
2. tasks/task-210b-kicad-artifact-schemas.md

Follow AGENTS.md exactly. Commit after 210a, then commit after 210b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 211

```text
Read and execute these task files in order:

1. tasks/task-211a-kicad-schematic-parser-tests.md
2. tasks/task-211b-kicad-schematic-parser.md

Follow AGENTS.md exactly. Commit after 211a, then commit after 211b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 212

```text
Read and execute these task files in order:

1. tasks/task-212a-schematic-extraction-policy-tests.md
2. tasks/task-212b-schematic-extraction-policy.md

Follow AGENTS.md exactly. Commit after 212a, then commit after 212b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 213

```text
Read and execute these task files in order:

1. tasks/task-213a-components-footprints-bom-tests.md
2. tasks/task-213b-components-footprints-bom.md

Follow AGENTS.md exactly. Commit after 213a, then commit after 213b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 214

```text
Read and execute these task files in order:

1. tasks/task-214a-board-routing-policy-tests.md
2. tasks/task-214b-board-routing-policy.md

Follow AGENTS.md exactly. Commit after 214a, then commit after 214b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 215

```text
Read and execute these task files in order:

1. tasks/task-215a-verification-fab-policy-tests.md
2. tasks/task-215b-verification-fab-policy.md

Follow AGENTS.md exactly. Commit after 215a, then commit after 215b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 216

```text
Read and execute these task files in order:

1. tasks/task-216a-vendor-order-approval-tests.md
2. tasks/task-216b-vendor-order-approval.md

Follow AGENTS.md exactly. Commit after 216a, then commit after 216b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 217

```text
Read and execute these task files in order:

1. tasks/task-217a-kicad-workflow-orchestration-tests.md
2. tasks/task-217b-kicad-workflow-orchestration.md

Follow AGENTS.md exactly. Commit after 217a, then commit after 217b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it.
```

## Batch 218

```text
Read and execute these task files in order:

1. tasks/task-218a-merlin-v2-version-release-tests.md
2. tasks/task-218b-merlin-v2-version-release.md

Follow AGENTS.md exactly. Commit after 218a, then commit after 218b. Do not batch commits. Run the verification command in each task. If signing blocks xcodebuild, rerun with signing disabled and record it. Only create tag v2.0.0 after 218b tests pass and the 218b commit succeeds.
```
