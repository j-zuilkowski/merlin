# Phase 266b — Finding Dedup Key

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 266a complete: failing tests for `Finding.dedupKey` and queue idempotency.

This phase gives `Finding` a stable, content-derived idempotency key and re-keys
`PendingAttentionQueue` by that key. After this fix a re-scan of an unchanged project
collapses onto the existing queue entries instead of growing `pending.json` without bound.

---

## Write to: Merlin/Discipline/Finding.swift

Full file content:

```swift
import Foundation

// MARK: - FindingCategory

enum FindingCategory: String, Codable, Sendable, CaseIterable {
    case phaseDrift
    case manualCoverageGap
    case docStaleReference
    case whyCommentMissing
    case proseReadabilityFail
    case versionBumpCandidate
    case overrideAuditAccumulation
}

// MARK: - Severity

enum Severity: String, Codable, Sendable, CaseIterable, Comparable {
    case block
    case nudge
    case silent

    private var sortOrder: Int {
        switch self {
        case .block:
            return 0
        case .nudge:
            return 1
        case .silent:
            return 2
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

// MARK: - Finding

struct Finding: Sendable, Identifiable, Codable, Equatable {
    let id: UUID
    let category: FindingCategory
    let severity: Severity
    let summary: String
    let detail: String
    let suggestedAction: String?
    let createdAt: Date
    let lastSeenAt: Date

    /// Stable, content-derived idempotency key.
    ///
    /// `id` is a fresh `UUID` minted on every scan, so it cannot identify a logical
    /// finding across runs. `dedupKey` is derived from the category and summary — the
    /// fields that define what the finding *is* — so a re-scan that re-discovers the
    /// same issue produces the same key. `PendingAttentionQueue` keys its storage on
    /// this value to collapse repeat findings onto a single persisted entry.
    var dedupKey: String {
        "\(category.rawValue)|\(summary)"
    }
}
```

---

## Write to: Merlin/Discipline/PendingAttentionQueue.swift

Full file content:

```swift
import Foundation

/// Persisted queue of discipline findings the user has not yet addressed.
/// Persists to `.merlin/pending.json`. Thread-safe via actor isolation.
actor PendingAttentionQueue {

    // MARK: - Storage

    private let storePath: String
    /// Keyed by `Finding.dedupKey` (content-derived), NOT `Finding.id`. The `id` is a
    /// fresh UUID on every scan, so keying by it would never collide and the queue
    /// would grow without bound. The dedup key is stable across re-scans.
    private var findings: [String: Finding] = [:]

    // MARK: - Init

    init(storePath: String) {
        self.storePath = storePath
        if let loaded = Self.loadFromDisk(storePath) {
            self.findings = Dictionary(
                loaded.map { ($0.dedupKey, $0) },
                uniquingKeysWith: { _, newer in newer }
            )
        }
    }

    // MARK: - API

    func add(_ finding: Finding) async {
        if let existing = findings[finding.dedupKey] {
            // Same logical finding seen again: keep the original identity and
            // creation time, advance only lastSeenAt.
            findings[finding.dedupKey] = Finding(
                id: existing.id,
                category: existing.category,
                severity: existing.severity,
                summary: existing.summary,
                detail: existing.detail,
                suggestedAction: existing.suggestedAction,
                createdAt: existing.createdAt,
                lastSeenAt: finding.lastSeenAt
            )
        } else {
            findings[finding.dedupKey] = finding
        }

        persist()
        TelemetryEmitter.shared.emit("discipline.finding.added", data: [
            "category": finding.category.rawValue,
            "severity": finding.severity.rawValue
        ])
    }

    func all() async -> [Finding] {
        findings.values.sorted { $0.createdAt < $1.createdAt }
    }

    func top(n: Int) async -> [Finding] {
        let sorted = findings.values.sorted {
            if $0.severity != $1.severity {
                return $0.severity < $1.severity
            }
            return $0.lastSeenAt > $1.lastSeenAt
        }
        return Array(sorted.prefix(n))
    }

    func dismiss(id: UUID, rationale: String) async {
        // The caller dismisses by the finding's display `id`. Storage is keyed by
        // dedupKey, so locate the entry whose value carries the matching id.
        guard let key = findings.first(where: { $0.value.id == id })?.key else {
            return
        }
        let removed = findings.removeValue(forKey: key)
        persist()
        if let removed {
            TelemetryEmitter.shared.emit("discipline.finding.dismissed", data: [
                "category": removed.category.rawValue,
                "rationale": rationale
            ])
        }
    }

    // MARK: - Persistence

    private func persist() {
        let list = Array(findings.values)
        guard let data = try? JSONEncoder().encode(list) else { return }
        let url = URL(fileURLWithPath: storePath)
        let parent = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: url, options: .atomic)
    }

    private static func loadFromDisk(_ path: String) -> [Finding]? {
        let url = URL(fileURLWithPath: path)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([Finding].self, from: data)
    }
}
```

---

## Fixes

- `Finding` gains the computed `dedupKey` property (category + summary). Stored fields,
  `Codable` conformance, and JSON shape are unchanged — `dedupKey` is computed, not
  encoded, so existing `pending.json` files still decode.
- `PendingAttentionQueue` storage re-keyed from `[UUID: Finding]` to `[String: Finding]`
  keyed by `dedupKey`. `add()` now collapses repeat findings; `dismiss(id:)` locates
  entries by scanning for the matching `value.id`; `loadFromDisk` rebuilds the dict by
  `dedupKey` (newer entry wins on a key collision in a legacy file).
- `PendingAttentionQueueTests.testTopNRespectsLimit` now seeds distinct summaries so the
  limit assertion exercises the top-N truncation path instead of the dedupe path.

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all phase 266a tests pass. No prior phase regresses.

## Commit

```bash
git add phases/phase-266b-finding-dedup-key.md \
    Merlin/Discipline/Finding.swift \
    Merlin/Discipline/PendingAttentionQueue.swift
git commit -m "Phase 266b — Finding dedup key"
```
