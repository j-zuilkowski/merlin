# Task 224a - DPO Review Queue UI Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
`DPOQueue` persists pending entries, but the review queue UI and accept/edit/decline flow are future scoped.

New surface introduced in task 224b:
  - `DPOReviewStore`
  - `DPOReviewQueueView`
  - accepted DPO entries move from pending to accepted corpus with non-empty `chosen`
  - declined entries are removed or archived without entering the corpus

TDD coverage:
  File 1 - `DPOReviewStoreTests`: load, accept, accept+edit, decline.
  File 2 - `DPOReviewQueueViewTests`: state wiring and disabled accept until chosen is non-empty.

---

## Add: MerlinTests/Unit/DPOReviewStoreTests.swift

Create tests that assert:

1. Pending entries load from `~/.merlin/lora/pending` compatible directories.
2. `accept(entryID:chosen:)` rejects empty chosen text.
3. `accept(entryID:chosen:)` writes an accepted JSONL/JSON corpus entry and removes the pending file.
4. `decline(entryID:)` removes or archives the pending file without corpus entry.
5. Corrupt pending files are skipped and do not block valid entries.

Use temporary directories only.

---

## Add: MerlinTests/Unit/DPOReviewQueueViewTests.swift

Create focused view-model tests if direct SwiftUI inspection is impractical.

Assert:

1. Selected entry text populates prompt/rejected/chosen fields.
2. Accept is disabled while chosen text is empty.
3. Accept+Edit passes edited chosen text to `DPOReviewStore`.
4. Decline removes the entry from the visible queue.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because DPO review UI/store types do not exist.

## Commit

```bash
git add MerlinTests/Unit/DPOReviewStoreTests.swift MerlinTests/Unit/DPOReviewQueueViewTests.swift
git commit -m "Task 224a - DPOReviewQueueTests (failing)"
```

