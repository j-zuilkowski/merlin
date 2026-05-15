# Phase 245b — DisciplineEngine

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 245a complete: failing tests for DisciplineEngine, ScanReport, and the circuit breaker.

This phase also introduces stub actors for the scanners not yet implemented (ManualCoverageScanner,
DocReferenceGraph, WhyCommentScanner, ProseReadabilityChecker). Each stub returns empty results.
Later phases (249–256) replace the stubs with real implementations.

---

## Write to

### Merlin/Discipline/ScanReport.swift (new file)

```swift
import Foundation

/// Result of a single `DisciplineEngine.scan` run.
struct ScanReport: Sendable {
    let findings: [Finding]
    let durationMs: Int
    let scannedAt: Date
}
```

### Merlin/Discipline/DisciplineEngine.swift (new file)

```swift
import Foundation

/// Central coordinator for the v2.2 Project Discipline Subsystem.
/// Runs all scanners, accumulates findings, integrates with the hook engine.
actor DisciplineEngine {

    // MARK: - Dependencies

    private let adapter: ProjectAdapter
    private let phaseScanner: PhaseScanner
    private let manualCoverageScanner: ManualCoverageScanner
    private let docReferenceGraph: DocReferenceGraph
    private let whyCommentScanner: WhyCommentScanner
    private let proseReadabilityChecker: ProseReadabilityChecker
    private let queue: PendingAttentionQueue

    // MARK: - Circuit breaker

    private var consecutiveFailures = 0
    private var isDisabled = false
    private let maxConsecutiveFailures = 3

    // MARK: - Test injection

    private let forceErrorForTesting: Bool

    // MARK: - Init

    init(
        adapter: ProjectAdapter,
        phaseScanner: PhaseScanner,
        manualCoverageScanner: ManualCoverageScanner,
        docReferenceGraph: DocReferenceGraph,
        whyCommentScanner: WhyCommentScanner,
        proseReadabilityChecker: ProseReadabilityChecker,
        storePath: String,
        forceErrorForTesting: Bool = false
    ) {
        self.adapter = adapter
        self.phaseScanner = phaseScanner
        self.manualCoverageScanner = manualCoverageScanner
        self.docReferenceGraph = docReferenceGraph
        self.whyCommentScanner = whyCommentScanner
        self.proseReadabilityChecker = proseReadabilityChecker
        self.queue = PendingAttentionQueue(storePath: storePath)
        self.forceErrorForTesting = forceErrorForTesting
    }

    // MARK: - Public API

    func scan(projectPath: String) async -> ScanReport {
        guard !isDisabled else {
            return ScanReport(findings: [], durationMs: 0, scannedAt: Date())
        }

        TelemetryEmitter.shared.emit("discipline.scan.start",
            data: ["trigger": "manual"])

        let start = Date()

        do {
            if forceErrorForTesting {
                throw DisciplineError.scanFailed("forced error for testing")
            }

            async let driftFindings  = phaseScanner.scan(projectPath: projectPath)
            async let coverageGaps   = manualCoverageScanner.scan(
                projectPath: projectPath, adapter: adapter)
            async let docRefs        = docReferenceGraph.build(projectPath: projectPath)
            async let whyTriggers    = whyCommentScanner.scan(
                projectPath: projectPath, adapter: adapter)

            let (drift, gaps, refs, why) = await (driftFindings, coverageGaps, docRefs, whyTriggers)

            var findings: [Finding] = []
            let now = Date()

            // Convert drift findings to queue findings
            for d in drift where d.severity == .red || d.severity == .orange {
                let f = Finding(
                    id: UUID(), category: .phaseDrift,
                    severity: d.severity == .red ? .block : .nudge,
                    summary: d.surface,
                    detail: d.evidence,
                    suggestedAction: d.suggestedAction,
                    createdAt: now, lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }

            // Coverage gaps
            for gap in gaps {
                let f = Finding(
                    id: UUID(), category: .manualCoverageGap, severity: .nudge,
                    summary: gap.surface, detail: "Manual coverage gap",
                    suggestedAction: gap.suggestedSection,
                    createdAt: now, lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }

            // Stale doc references
            for ref in refs {
                let f = Finding(
                    id: UUID(), category: .docStaleReference, severity: .silent,
                    summary: ref.codeSymbol, detail: "Referenced in \(ref.docFile)",
                    suggestedAction: "Review doc section",
                    createdAt: now, lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }

            // WHY-comment missing
            for trigger in why where !trigger.hasNearbyComment {
                let f = Finding(
                    id: UUID(), category: .whyCommentMissing, severity: .nudge,
                    summary: "\(trigger.file):\(trigger.line)",
                    detail: trigger.context,
                    suggestedAction: "Add WHY comment: \(trigger.reason)",
                    createdAt: now, lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }

            consecutiveFailures = 0
            let durationMs = Int(Date().timeIntervalSince(start) * 1000)
            TelemetryEmitter.shared.emit("discipline.scan.complete",
                data: ["findings_count": findings.count, "duration_ms": durationMs])
            return ScanReport(findings: findings, durationMs: durationMs, scannedAt: now)

        } catch {
            consecutiveFailures += 1
            TelemetryEmitter.shared.emit("discipline.scan.error",
                data: ["error": String(describing: error)])
            if consecutiveFailures >= maxConsecutiveFailures {
                isDisabled = true
                TelemetryEmitter.shared.emit("discipline.disabled",
                    data: ["consecutive_failures": consecutiveFailures])
            }
            return ScanReport(findings: [], durationMs: 0, scannedAt: Date())
        }
    }

    func pendingAttention(projectPath: String) async -> [Finding] {
        await queue.top(n: 50)
    }

    func dismiss(findingID: UUID, rationale: String) async {
        await queue.dismiss(id: findingID, rationale: rationale)
    }

    // MARK: - Errors

    enum DisciplineError: Error, Sendable {
        case scanFailed(String)
    }
}
```

### Merlin/Discipline/ManualCoverageScanner.swift (new file — stub)

```swift
import Foundation

/// Stub implementation — replaced by full scanner in phase 249b.
actor ManualCoverageScanner {
    func scan(projectPath: String, adapter: ProjectAdapter) async -> [ManualCoverageGap] {
        []
    }
}

struct ManualCoverageGap: Sendable {
    let surface: String
    let surfaceType: String
    let firstSeen: Date
    let suggestedSection: String?
}
```

### Merlin/Discipline/DocReferenceGraph.swift (new file — stub)

```swift
import Foundation

/// Stub implementation — replaced by full graph in phase 251b.
actor DocReferenceGraph {
    func build(projectPath: String) async -> [DocReference] { [] }
    func staleReferences(against changedSymbols: [String]) async -> [DocReference] { [] }
}

struct DocReference: Sendable {
    let docFile: String
    let docSection: String?
    let codeSymbol: String
    let sourceFile: String?
}
```

### Merlin/Discipline/WhyCommentScanner.swift (new file — stub)

```swift
import Foundation

/// Stub implementation — replaced by full scanner in phase 254b.
actor WhyCommentScanner {
    func scan(projectPath: String, adapter: ProjectAdapter) async -> [WhyCommentTrigger] { [] }
}

struct WhyCommentTrigger: Sendable {
    let pattern: String
    let reason: String
    let file: String
    let line: Int
    let context: String
    let hasNearbyComment: Bool
}
```

### Merlin/Discipline/ProseReadabilityChecker.swift (new file — stub)

```swift
import Foundation

/// Stub implementation — replaced by full checker in phase 256b.
actor ProseReadabilityChecker {
    func check(docFile: String, targetGrade: Double) async -> ReadabilityFinding {
        ReadabilityFinding(docFile: docFile, measuredGrade: 0,
                           targetGrade: targetGrade, suggestions: [])
    }
}

struct ReadabilityFinding: Sendable {
    let docFile: String
    let measuredGrade: Double
    let targetGrade: Double
    let suggestions: [String]
}
```

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

Expected: **BUILD SUCCEEDED** and all phase 245a tests pass. No prior phase regresses.

## Commit

```bash
git add phases/phase-245b-discipline-engine.md \
    Merlin/Discipline/ScanReport.swift \
    Merlin/Discipline/DisciplineEngine.swift \
    Merlin/Discipline/ManualCoverageScanner.swift \
    Merlin/Discipline/DocReferenceGraph.swift \
    Merlin/Discipline/WhyCommentScanner.swift \
    Merlin/Discipline/ProseReadabilityChecker.swift
git commit -m "Phase 245b — DisciplineEngine + ScanReport + scanner stubs"
```
