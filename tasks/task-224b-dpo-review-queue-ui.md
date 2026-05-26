# Task 224b - DPO Review Queue UI

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 224a complete: failing DPO review queue tests exist.

---

## Add: Merlin/Engine/DPOReviewStore.swift

Implement review queue operations over `DPOQueue` storage.

Rules:

1. Pending entries stay in `~/.merlin/lora/pending`.
2. Accepted entries require non-empty `chosen`.
3. Accepted entries move to a durable reviewed corpus path under `~/.merlin/lora/`.
4. Declined entries do not enter training corpus.
5. All writes are atomic.

---

## Add: Merlin/Views/Settings/DPOReviewQueueView.swift

Implement a Settings > LoRA review queue section.

Controls:

1. Pending list.
2. Prompt/rejected read-only preview.
3. Editable chosen response.
4. Accept, Accept+Edit, Decline actions.

---

## Edit: Merlin/Views/Settings/LoRASettingsSection.swift

Embed `DPOReviewQueueView` below the LoRA status section.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. DPO review tests pass.

## Commit

```bash
git add Merlin/Engine/DPOReviewStore.swift Merlin/Views/Settings/DPOReviewQueueView.swift Merlin/Views/Settings/LoRASettingsSection.swift MerlinTests/Unit/DPOReviewStoreTests.swift MerlinTests/Unit/DPOReviewQueueViewTests.swift
git commit -m "Task 224b - DPO review queue UI"
```

