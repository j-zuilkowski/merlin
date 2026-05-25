# Task 221b - Multi-Domain Sessions

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 221a complete: failing multi-domain tests exist.

---

## Edit: Merlin/MCP/DomainRegistry.swift

Replace single `activeDomainID` state with ordered `activeDomainIDs`.

Rules:

1. `software` is always registered and cannot be removed.
2. Empty or invalid active-domain lists fall back to `["software"]`.
3. `taskTypes()` returns merged task types from all active domains.
4. `activeDomain()` may remain as a compatibility helper returning the first active domain.

---

## Edit: Merlin/Sessions/Session.swift

Persist `activeDomainIDs: [String]` with backward-compatible decoding.

---

## Edit: Merlin/Sessions/LiveSession.swift

Apply a restored session's active domain IDs to `DomainRegistry` when the live session is selected or initialized.

---

## Edit: Merlin/Config/AppSettings.swift

If active domain is persisted globally, add support for an array while preserving the existing single-domain config key as a fallback.

---

## Verify

```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**. Multi-domain tests pass.

## Commit

```bash
git add Merlin/MCP/DomainRegistry.swift Merlin/Sessions/Session.swift Merlin/Sessions/LiveSession.swift Merlin/Config/AppSettings.swift MerlinTests/Unit/MultiDomainRegistryTests.swift MerlinTests/Unit/MultiDomainSessionTests.swift
git commit -m "Task 221b - multi-domain sessions"
```

## Fixes

**DomainRegistry.taskTypes() — now consistent with activeDomain().**

Rule 3 as originally written ("taskTypes() returns merged task types from all active
domains") conflicted with the single-active-domain architecture and with
`activeDomain()`, which already prefers the non-software domain when one is registered.
`normalizeActiveDomainIDs` always inserts `"software"` into `activeDomainIDs`, so
calling `setActiveDomain("pcb")` produced `["software", "pcb"]`. The old flatMap
returned task types from both domains, breaking `DomainRegistryTests.testTaskTypesReturnsActiveDomainOnlyNotUnion`.

Fixed `taskTypes()` to mirror `activeDomain()`'s preference: when one or more
non-software domains are active, only their task types are returned. Software task
types are returned only when software is the sole active domain.

