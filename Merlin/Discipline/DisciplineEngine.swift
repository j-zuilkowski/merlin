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

            async let driftFindings = phaseScanner.scan(projectPath: projectPath)
            async let coverageGaps = manualCoverageScanner.scan(
                projectPath: projectPath, adapter: adapter)
            async let docRefs = docReferenceGraph.build(projectPath: projectPath)
            async let whyTriggers = whyCommentScanner.scan(
                projectPath: projectPath, adapter: adapter)

            let (drift, gaps, refs, why) = await (driftFindings, coverageGaps, docRefs, whyTriggers)

            var findings: [Finding] = []
            let now = Date()

            // Convert drift findings to queue findings.
            for d in drift where d.severity == .red || d.severity == .orange {
                let f = Finding(
                    id: UUID(),
                    category: .phaseDrift,
                    severity: d.severity == .red ? .block : .nudge,
                    summary: d.surface,
                    detail: d.evidence,
                    suggestedAction: d.suggestedAction,
                    createdAt: now,
                    lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }

            // Coverage gaps.
            for gap in gaps {
                let f = Finding(
                    id: UUID(),
                    category: .manualCoverageGap,
                    severity: .nudge,
                    summary: gap.surface,
                    detail: "Manual coverage gap",
                    suggestedAction: gap.suggestedSection,
                    createdAt: now,
                    lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }

            // Stale doc references.
            for ref in refs {
                let f = Finding(
                    id: UUID(),
                    category: .docStaleReference,
                    severity: .silent,
                    summary: ref.codeSymbol,
                    detail: "Referenced in \(ref.docFile)",
                    suggestedAction: "Review doc section",
                    createdAt: now,
                    lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }

            // WHY-comment missing.
            for trigger in why where !trigger.hasNearbyComment {
                let f = Finding(
                    id: UUID(),
                    category: .whyCommentMissing,
                    severity: .nudge,
                    summary: "\(trigger.file):\(trigger.line)",
                    detail: trigger.context,
                    suggestedAction: "Add WHY comment: \(trigger.reason)",
                    createdAt: now,
                    lastSeenAt: now
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
        _ = projectPath
        return await queue.top(n: 50)
    }

    func dismiss(findingID: UUID, rationale: String) async {
        await queue.dismiss(id: findingID, rationale: rationale)
    }

    // MARK: - Errors

    enum DisciplineError: Error, Sendable {
        case scanFailed(String)
    }
}
