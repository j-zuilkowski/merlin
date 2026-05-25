# Phase 221a - Multi-Domain Session Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Architecture currently supports one active domain and defers multi-domain sessions.

New surface introduced in phase 221b:
  - `DomainRegistry.activeDomains()` - ordered active domain list
  - `DomainRegistry.setActiveDomains(ids:)`
  - `DomainRegistry.taskTypes()` merges all active domains
  - `Session.activeDomainIDs` persists the per-session domain set

TDD coverage:
  File 1 - `MultiDomainRegistryTests`: domain activation, fallback, merged task types.
  File 2 - `MultiDomainSessionTests`: session persistence and restore of active domains.

---

## Add: MerlinTests/Unit/MultiDomainRegistryTests.swift

Create tests that assert:

1. A registry can activate multiple registered domains in a stable order.
2. `taskTypes()` returns task types from every active domain.
3. Unregistered domain IDs are ignored or rejected consistently without dropping `software`.
4. Unregistering an active domain removes only that domain and keeps remaining active domains.
5. `software` remains the fallback when no explicit active domain list is valid.

---

## Add: MerlinTests/Unit/MultiDomainSessionTests.swift

Create tests that assert:

1. `Session` encodes and decodes `activeDomainIDs`.
2. Missing `activeDomainIDs` in older session JSON restores to `["software"]`.
3. `LiveSession` applies restored domains to `DomainRegistry` when a session becomes active.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** because only single-domain APIs exist.

## Commit

```bash
git add MerlinTests/Unit/MultiDomainRegistryTests.swift MerlinTests/Unit/MultiDomainSessionTests.swift
git commit -m "Phase 221a - MultiDomainSessionTests (failing)"
```

