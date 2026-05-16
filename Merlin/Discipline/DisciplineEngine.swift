import Foundation

/// Central coordinator for the v2.2 Project Discipline Subsystem.
/// Runs all scanners, accumulates findings, integrates with the hook engine.
actor DisciplineEngine {

    // MARK: - Dependencies

    private var adapter: ProjectAdapter
    private let phaseScanner: PhaseScanner
    private let manualCoverageScanner: ManualCoverageScanner
    private let docReferenceGraph: DocReferenceGraph
    private let whyCommentScanner: WhyCommentScanner
    private let proseReadabilityChecker: ProseReadabilityChecker
    private let queue: PendingAttentionQueue
    private let overrideLog: OverrideAuditLog

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
        self.overrideLog = OverrideAuditLog(
            logPath: URL(fileURLWithPath: storePath)
                .deletingLastPathComponent()
                .appendingPathComponent("override-log.jsonl").path)
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
            async let docRefs = docReferenceGraph.danglingReferences(projectPath: projectPath)
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

            // Dangling doc references - doc mentions of code symbols that do not
            // exist in the source tree. Silent severity: informational, never blocks.
            for ref in refs {
                let f = Finding(
                    id: UUID(),
                    category: .docStaleReference,
                    severity: .silent,
                    summary: ref.codeSymbol,
                    detail: "Referenced in \(ref.docFile) but not found in source tree",
                    suggestedAction: "Remove the stale reference or restore the symbol",
                    createdAt: now,
                    lastSeenAt: now
                )
                await queue.add(f)
                findings.append(f)
            }

            // WHY-comment triggers. An inline `rationale-not-needed:` annotation is
            // recorded as a viaAnnotation override; an un-annotated trigger with no
            // nearby comment becomes a finding.
            for trigger in why {
                if let rationale = trigger.overrideRationale {
                    let entry = OverrideEntry(
                        timestamp: now,
                        category: FindingCategory.whyCommentMissing.rawValue,
                        file: trigger.file,
                        line: trigger.line,
                        rationale: rationale,
                        userDismissed: false,
                        viaAnnotation: true,
                        annotationText: rationale
                    )
                    try? await overrideLog.record(entry)
                } else if !trigger.hasNearbyComment {
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
            }

            // Prose readability - run the checker over project doc files.
            for docFile in Self.enumerateDocFiles(projectPath: projectPath) {
                let targetGrade = Self.targetGrade(for: docFile, adapter: adapter)
                let result = await proseReadabilityChecker.check(
                    docFile: docFile, targetGrade: targetGrade)
                guard result.measuredGrade > result.targetGrade else { continue }
                let f = Finding(
                    id: UUID(),
                    category: .proseReadabilityFail,
                    severity: .nudge,
                    summary: URL(fileURLWithPath: docFile).lastPathComponent,
                    detail: String(
                        format: "Readability grade %.1f exceeds target %.1f",
                        result.measuredGrade, result.targetGrade),
                    suggestedAction: result.suggestions.first
                        ?? "Simplify the prose in this document",
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

    func dismiss(finding: Finding, rationale: String) async {
        await queue.dismiss(id: finding.id, rationale: rationale)
        let entry = OverrideEntry(
            timestamp: Date(),
            category: finding.category.rawValue,
            file: finding.summary,
            line: 0,
            rationale: rationale,
            userDismissed: true,
            viaAnnotation: false,
            annotationText: nil
        )
        try? await overrideLog.record(entry)
    }

    /// Runs the weekly override-accumulation review, adding an
    /// `.overrideAuditAccumulation` finding when a category is dismissed too often.
    func runWeeklyOverrideReview() async {
        await overrideLog.weeklyReview(queue: queue)
    }

    // MARK: - Adapter

    /// Replaces the engine's adapter at runtime. Called once the project's real adapter
    /// is resolved from `.merlin/project.toml` — the engine bootstraps with a stub.
    func setAdapter(_ adapter: ProjectAdapter) {
        self.adapter = adapter
    }

    /// The adapter the engine currently scans with.
    func currentAdapter() -> ProjectAdapter {
        adapter
    }

    /// Resolves a project's discipline adapter: reads `.merlin/project.toml`, looks the
    /// adapter key up in `registry`, and falls back to the Swift stub when there is no
    /// config or the key is unknown.
    static func resolveProjectAdapter(
        projectPath: String,
        registry: AdapterRegistry = .shared
    ) async -> ProjectAdapter {
        let stub = ProjectAdapter.makeStub(language: "swift")
        guard !projectPath.isEmpty else { return stub }
        let loader = ProjectConfigLoader()
        guard loader.exists(projectPath: projectPath) else { return stub }
        do {
            let config = try await loader.load(projectPath: projectPath)
            return try await registry.adapter(for: config.adapter)
        } catch {
            return stub
        }
    }

    // MARK: - Doc-file helpers

    private static func enumerateDocFiles(projectPath: String) -> [String] {
        var files: [String] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return files }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            files.append(url.path)
        }
        return files
    }

    /// Target Flesch-Kincaid grade for a doc file. Architecture-related docs allow a
    /// higher grade (11.0); everything else uses the adapter's configured grade for a
    /// matching doc kind, falling back to 9.0.
    private static func targetGrade(
        for docFile: String, adapter: ProjectAdapter
    ) -> Double {
        let name = URL(fileURLWithPath: docFile).lastPathComponent.lowercased()
            .replacingOccurrences(of: "_", with: "-")
        if name.contains("architecture") {
            return 11.0
        }
        for (pattern, grade) in adapter.docTargetGrade {
            let normalized = pattern.lowercased().replacingOccurrences(of: "_", with: "-")
            if name.contains(normalized) {
                return grade
            }
        }
        return 9.0
    }

    // MARK: - Errors

    enum DisciplineError: Error, Sendable {
        case scanFailed(String)
    }
}
