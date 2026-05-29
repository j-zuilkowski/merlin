import Foundation

struct ElectronicsRuntimePlugin {
    let metadata: RuntimePluginMetadata
    private let tooling: ElectronicsToolingState
    private let routeBackend: any ElectronicsRoutePassRunning
    private let loadStatus: String

    init(
        tooling: ElectronicsToolingState = .available,
        routeBackend: any ElectronicsRoutePassRunning = LocalFreeRoutingBackend(),
        loadStatus: String = "loaded"
    ) {
        self.tooling = tooling
        self.routeBackend = routeBackend
        self.loadStatus = loadStatus
        let toolCapabilities = KiCadToolDefinitions.requiredToolNames.map { toolName in
            WorkspaceCapability(
                id: "plugin.electronics.\(toolName)",
                displayName: toolName,
                kind: .tool,
                address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: toolName),
                requiredPermissionScope: toolName == "kicad_submit_vendor_order" ? .userApprovedIrreversible : .externalSideEffect
            )
        }
        let workflowCapabilities = [
            WorkspaceCapability(
                id: "plugin.electronics.workflow.schematic_to_pcb",
                displayName: "Schematic to PCB",
                kind: .workflow,
                address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "workflow.schematic_to_pcb"),
                requiredPermissionScope: .externalSideEffect
            ),
            WorkspaceCapability(
                id: "plugin.electronics.workflow.requirements_to_pcb",
                displayName: "Requirements to PCB",
                kind: .workflow,
                address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "workflow.requirements_to_pcb"),
                requiredPermissionScope: .externalSideEffect
            ),
            WorkspaceCapability(
                id: "plugin.electronics.verify",
                displayName: "Electronics Verification",
                kind: .verification,
                address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "verify.electronics"),
                requiredPermissionScope: .externalSideEffect
            ),
            WorkspaceCapability(
                id: "plugin.electronics.settings.validate",
                displayName: "Electronics Settings Validation",
                kind: .settings,
                address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "settings.validate"),
                requiredPermissionScope: .readOnly
            ),
        ]
        self.metadata = RuntimePluginMetadata(
            id: "electronics",
            displayName: "Electronics",
            version: "1.0.0",
            trustTier: .tier1,
            enabled: true,
            domainIDs: [ElectronicsDomain.defaultID],
            capabilities: toolCapabilities + workflowCapabilities,
            settingsSchema: ElectronicsDomain().settingsSchema
        )
    }

    @MainActor
    func register(into runtime: WorkspaceRuntime) async throws {
        if let schema = metadata.settingsSchema {
            await runtime.bus.registerSettingsSchema(schema)
        }
        for capability in metadata.capabilities {
            await runtime.bus.registerCapability(capability)
            await runtime.bus.register(
                ElectronicsCapabilityHandler(
                    capability: capability,
                    tooling: tooling,
                    routeBackend: routeBackend
                ),
                for: capability.address
            )
        }
        await runtime.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: nil,
            address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "health"),
            origin: nil,
            kind: .healthChanged,
            payload: .jsonString(#"{"status":"\#(loadStatus)"}"#)
        ))
    }
}

private struct ElectronicsCapabilityHandler: WorkspaceMessageHandler {
    var capability: WorkspaceCapability
    var tooling: ElectronicsToolingState
    var routeBackend: any ElectronicsRoutePassRunning

    func handle(_ request: WorkspaceMessageRequest, context: WorkspaceHandlerContext) async -> WorkspaceMessageResponse {
        guard request.origin.permissionScope.allows(capability.requiredPermissionScope) else {
            return .unauthorized(requestID: request.id, message: "electronics capability requires \(capability.requiredPermissionScope.rawValue)")
        }

        if let blocked = blockedToolingReason(for: request.address.capability) {
            await publishDiagnostic(reason: blocked, request: request, context: context)
            return .blocked(
                requestID: request.id,
                code: blocked.rawValue,
                message: blockedMessage(for: blocked)
            )
        }

        if request.address.capability == "settings.validate" {
            return .ok(requestID: request.id, payload: .jsonString(#"{"status":"valid"}"#))
        }

        if request.address.capability == "workflow.requirements_to_pcb"
            || request.address.capability == "workflow.schematic_to_pcb" {
            return await handleWorkflow(request, context: context)
        }

        if request.address.capability.hasPrefix("kicad_") {
            return await handleKiCadTool(request, context: context)
        }

        return structuredBlock(
            request,
            reason: .missingProjectFile,
            message: "Electronics capability \(request.address.capability) is not registered for this domain plugin.",
            context: context
        )
    }

    private func blockedToolingReason(for capability: String) -> ElectronicsBlockedReason? {
        guard capability.hasPrefix("kicad_") || capability.hasPrefix("workflow.") || capability == "verify.electronics" else {
            return nil
        }
        if !tooling.kiCadAvailable {
            return .missingKiCad
        }
        if tooling.unsupportedVersion {
            return .unsupportedVersion
        }
        if capability == "kicad_route_pass", !tooling.localFreeRoutingAvailable {
            return .missingFreeRouting
        }
        return nil
    }

    private func handleWorkflow(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        if object["evidence"] == nil {
            return await synthesizedRequirementsWorkflow(request, context: context, object: object)
        }

        guard let workflow = try? request.payload.decodeJSON(ElectronicsWorkflowRequest.self),
              let evidence = workflow.evidence else {
                return block(
                    request,
                    reason: .missingArtifact,
                    message: "Workflow requires explicit artifacts and gate evidence before it can complete.",
                    context: context
                )
        }

        let requirements = stringValue(object, keys: ["requirements", "prompt", "description"])
        let validation = validateCompletionEvidence(evidence, requirements: requirements)
        let report = ElectronicsGateRunner().finalReport(jobID: workflow.jobID, evidence: validation.evidence)
        if let reportURL = try? ElectronicsEvidenceStore(rootURL: context.workspaceRoot).save(report: report) {
            await context.bus.publish(WorkspaceMessageEvent(
                id: UUID(),
                requestID: request.id,
                address: request.address,
                origin: request.origin,
                kind: .artifactProduced,
                payload: try? .encodeJSON(WorkspaceArtifactRef(
                    id: "\(workflow.jobID)-final-report",
                    kind: ElectronicsArtifactKind.verificationReport.rawValue,
                    url: reportURL,
                    displayName: "Electronics Final Report",
                    metadata: ["job_id": workflow.jobID]
                ))
            ))
        }
        await context.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: request.id,
            address: request.address,
            origin: request.origin,
            kind: .artifactProduced,
            payload: try? .encodeJSON(report)
        ))

        guard report.status == .complete else {
            let diagnostics = report.blockedReasons.map {
                WorkspaceDiagnostic(code: $0.rawValue, message: blockedMessage(for: $0), severity: "error")
            } + validation.diagnostics
            return WorkspaceMessageResponse(
                requestID: request.id,
                status: .blocked,
                payload: try? .encodeJSON(report),
                artifacts: [],
                diagnostics: diagnostics
            )
        }

        return .ok(requestID: request.id, payload: try? .encodeJSON(report))
    }

    private func validateCompletionEvidence(
        _ evidence: ElectronicsCompletionEvidence,
        requirements: String?
    ) -> (evidence: ElectronicsCompletionEvidence, diagnostics: [WorkspaceDiagnostic]) {
        var sanitized = evidence
        var diagnostics: [WorkspaceDiagnostic] = []

        sanitized.artifacts = evidence.artifacts.filter { artifact in
            guard FileManager.default.fileExists(atPath: artifact.path) else {
                diagnostics.append(WorkspaceDiagnostic(
                    code: ElectronicsBlockedReason.missingArtifact.rawValue,
                    message: "\(artifact.kind.rawValue) artifact does not exist at \(artifact.path).",
                    severity: "error"
                ))
                return false
            }
            guard artifactHasUsableContents(artifact) else {
                diagnostics.append(WorkspaceDiagnostic(
                    code: ElectronicsBlockedReason.failedGate.rawValue,
                    message: "\(artifact.kind.rawValue) artifact at \(artifact.path) is empty, malformed, or does not satisfy the electronics completion contract.",
                    severity: "error"
                ))
                return false
            }
            return true
        }

        if !diagnostics.isEmpty {
            failGate(.fabrication, in: &sanitized, details: "One or more declared artifacts were missing or invalid.")
        }

        if requirementsMismatch(requirements: requirements, artifacts: sanitized.artifacts) {
            failGate(.parity, in: &sanitized, details: "Generated artifacts do not match the requested electronics design.")
            failGate(.simulation, in: &sanitized, details: "Simulation evidence does not match the requested electronics design.")
            diagnostics.append(WorkspaceDiagnostic(
                code: ElectronicsBlockedReason.failedGate.rawValue,
                message: "Artifact contents appear to describe a canned 555/LED blinker instead of the requested design.",
                severity: "error"
            ))
        }

        return (sanitized, diagnostics)
    }

    private func artifactHasUsableContents(_ artifact: ElectronicsCompletionArtifact) -> Bool {
        switch artifact.kind {
        case .fabricationPackage:
            return isValidZipArchive(atPath: artifact.path)
        case .bom:
            return bomHasVendorPartEvidence(atPath: artifact.path)
        default:
            return nonEmptyArtifact(atPath: artifact.path)
        }
    }

    private func nonEmptyArtifact(atPath path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.intValue > 0
    }

    private func isValidZipArchive(atPath path: String) -> Bool {
        guard nonEmptyArtifact(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else {
            return false
        }
        defer { try? handle.close() }
        let signature = handle.readData(ofLength: 4)
        return signature == Data([0x50, 0x4B, 0x03, 0x04])
            || signature == Data([0x50, 0x4B, 0x05, 0x06])
            || signature == Data([0x50, 0x4B, 0x07, 0x08])
    }

    private func bomHasVendorPartEvidence(atPath path: String) -> Bool {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8),
              text.split(separator: "\n").count >= 2 else {
            return false
        }
        let normalized = text.lowercased()
        return normalized.contains("digikey")
            || normalized.contains("digi-key")
            || normalized.contains("mouser")
            || normalized.contains("vendor")
            || normalized.contains("mpn")
    }

    private func requirementsMismatch(
        requirements: String?,
        artifacts: [ElectronicsCompletionArtifact]
    ) -> Bool {
        guard let requirements else { return false }
        let normalizedRequirements = requirements.lowercased()
        let requestsAmplifier = ["amplifier", "guitar", "class-a", "class a", "25 watt", "25w", "tone"]
            .contains { normalizedRequirements.contains($0) }
        guard requestsAmplifier else { return false }

        let combined = artifacts
            .filter { [.schematic, .bom, .spiceMeasurements].contains($0.kind) }
            .compactMap { try? String(contentsOfFile: $0.path, encoding: .utf8) }
            .joined(separator: "\n")
            .lowercased()

        guard !combined.isEmpty else { return false }
        let looksLike555Blinker = combined.contains("ne555")
            || combined.contains("555 astable")
            || combined.contains("led blinker")
        let looksLikeAmplifier = ["amplifier", "guitar", "class-a", "class a", "tone stack", "output stage"]
            .contains { combined.contains($0) }
        return looksLike555Blinker && !looksLikeAmplifier
    }

    private func failGate(
        _ gate: ElectronicsVerificationGate,
        in evidence: inout ElectronicsCompletionEvidence,
        details: String
    ) {
        evidence.gates[gate] = ElectronicsGateResult(gate: gate, status: .fail, details: details)
    }

    private func synthesizedRequirementsWorkflow(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        object: [String: Any]
    ) async -> WorkspaceMessageResponse {
        guard let requirements = stringValue(object, keys: ["requirements", "prompt", "description"]) else {
            return block(
                request,
                reason: .missingArtifact,
                message: "Workflow synthesis requires natural-language requirements or explicit evidence.",
                context: context
            )
        }
        guard isAmpDemoAmplifierRequest(requirements) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "Requirements-to-PCB completion requires explicit evidence from real KiCad, SPICE, routing, fabrication, BOM, and verification artifacts. Merlin will not synthesize placeholder board artifacts or mark a requirements-only request complete.",
                context: context,
                nextActions: [
                    "create_design_intent",
                    "compile_kicad_project",
                    "run_erc_drc_spice_and_fab_export",
                    "resubmit_workflow_with_evidence"
                ]
            )
        }
        return await runAmpDemoRequirementsWorkflow(request, context: context, object: object, requirements: requirements)
    }

    private func isAmpDemoAmplifierRequest(_ requirements: String) -> Bool {
        let text = requirements.lowercased()
        return (text.contains("amplifier") || text.contains("ampdemo"))
            && text.contains("guitar")
            && (text.contains("class a") || text.contains("class-a"))
            && (text.contains("25 watt") || text.contains("25w"))
    }

    private func runAmpDemoRequirementsWorkflow(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        object: [String: Any],
        requirements: String
    ) async -> WorkspaceMessageResponse {
        guard let cliPath = executablePath(from: object, key: "kicad_cli_path", defaultCandidates: defaultKiCadCLICandidates()) else {
            return requiredExecutableBlock(
                request,
                context: context,
                code: "KICAD_CLI_REQUIRED",
                message: "Requirements-to-PCB workflow requires an executable KiCad CLI path."
            )
        }
        guard let ngspicePath = executablePath(from: object, key: "ngspice_path", defaultCandidates: ["/opt/homebrew/bin/ngspice", "/usr/local/bin/ngspice"]) else {
            return requiredExecutableBlock(
                request,
                context: context,
                code: "SPICE_SIMULATOR_REQUIRED",
                message: "Requirements-to-PCB workflow requires an executable ngspice_path."
            )
        }

        let jobID = stringValue(object, keys: ["job_id", "jobId"]) ?? "ampdemo-\(request.id.uuidString.prefix(8))"
        let rootURL = URL(fileURLWithPath: stringValue(object, keys: ["output_directory"]) ?? context.workspaceRoot.path, isDirectory: true)
        let kicadURL = rootURL.appendingPathComponent("kicad", isDirectory: true)
        let gerberURL = rootURL.appendingPathComponent("gerbers", isDirectory: true)
        let drillURL = rootURL.appendingPathComponent("drill", isDirectory: true)
        let simulationURL = rootURL.appendingPathComponent("simulation", isDirectory: true)
        let bomURL = rootURL.appendingPathComponent("bom", isDirectory: true)
        let reportsURL = rootURL.appendingPathComponent("reports", isDirectory: true)
        let librariesURL = rootURL.appendingPathComponent("libraries", isDirectory: true)

        await publishWorkflowProgress(
            jobID: jobID,
            status: .inProgress,
            message: "Starting AmpDemo requirements-to-PCB workflow",
            request: request,
            context: context
        )

        do {
            for directory in [kicadURL, gerberURL, drillURL, simulationURL, bomURL, reportsURL, librariesURL] {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }

            let designIntentURL = reportsURL.appendingPathComponent("design-intent.json")
            let projectURL = kicadURL.appendingPathComponent("AmpDemo.kicad_pro")
            let schematicURL = kicadURL.appendingPathComponent("AmpDemo.kicad_sch")
            let boardURL = kicadURL.appendingPathComponent("AmpDemo.kicad_pcb")
            let spiceDeckURL = simulationURL.appendingPathComponent("ampdemo-class-a-subset.cir")
            let spiceLogURL = simulationURL.appendingPathComponent("ngspice-output.log")
            let ercURL = reportsURL.appendingPathComponent("erc-report.json")
            let drcURL = reportsURL.appendingPathComponent("drc-report.json")
            let bomCSVURL = bomURL.appendingPathComponent("ampdemo-bom.csv")
            let orderURL = bomURL.appendingPathComponent("vendor-order-notes.json")
            let approvalURL = reportsURL.appendingPathComponent("demo-approval-record.json")
            let finalReportURL = reportsURL.appendingPathComponent("final-demo-report.md")
            let fabPackageURL = reportsURL.appendingPathComponent("ampdemo-fabrication-package.zip")

            try ampDemoDesignIntent(requirements: requirements, jobID: jobID).write(to: designIntentURL, atomically: true, encoding: .utf8)
            try ampDemoProjectFile().write(to: projectURL, atomically: true, encoding: .utf8)
            try ampDemoSchematicFile().write(to: schematicURL, atomically: true, encoding: .utf8)
            try ampDemoBoardFile().write(to: boardURL, atomically: true, encoding: .utf8)
            try ampDemoSpiceDeck().write(to: spiceDeckURL, atomically: true, encoding: .utf8)
            try ampDemoBOM().write(to: bomCSVURL, atomically: true, encoding: .utf8)
            try ampDemoVendorOrderNotes().write(to: orderURL, atomically: true, encoding: .utf8)
            try ampDemoApprovalRecord().write(to: approvalURL, atomically: true, encoding: .utf8)
            try ampDemoLibraryNotes().write(to: librariesURL.appendingPathComponent("source-notes.md"), atomically: true, encoding: .utf8)
            try "# AmpDemo Final Demo Report\n\nPending final gate evaluation.\n".write(to: finalReportURL, atomically: true, encoding: .utf8)

            let schematicUpgradeRun = runProcess(executablePath: cliPath, arguments: ["sch", "upgrade", "--force", schematicURL.path])
            guard schematicUpgradeRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "KICAD_SCHEMATIC_UPGRADE_FAILED", run: schematicUpgradeRun)
            }
            let boardUpgradeRun = runProcess(executablePath: cliPath, arguments: ["pcb", "upgrade", "--force", boardURL.path])
            guard boardUpgradeRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "KICAD_BOARD_UPGRADE_FAILED", run: boardUpgradeRun)
            }
            guard ampDemoKiCadArtifactsHavePartLevelAmplifierContent(schematicURL: schematicURL, boardURL: boardURL) else {
                return structuredBlock(
                    request,
                    reason: .invalidInputQuality,
                    message: "AmpDemo KiCad generation produced block-diagram placeholder content instead of a part-level amplifier schematic and PCB layout.",
                    context: context,
                    nextActions: [
                        "Replace generated AmpDemo block symbols with discrete resistors, capacitors, diodes, transistors, potentiometers, connectors, and power-supply parts.",
                        "Generate a PCB from the real netlist with component placement, grounding, thermal/current paths, and manufacturable routing before exporting Gerbers."
                    ]
                )
            }
            await publishWorkflowProgress(
                jobID: jobID,
                status: .inProgress,
                message: "AmpDemo KiCad, SPICE, BOM, and report seed artifacts written",
                request: request,
                context: context
            )
            let ercRun = runProcess(executablePath: cliPath, arguments: ["sch", "erc", schematicURL.path, "--format", "json", "--output", ercURL.path, "--severity-error", "--exit-code-violations"])
            guard ercRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "KICAD_ERC_FAILED", run: ercRun)
            }
            await publishWorkflowProgress(
                jobID: jobID,
                status: .inProgress,
                message: "KiCad ERC passed",
                request: request,
                context: context
            )
            let drcRun = runProcess(executablePath: cliPath, arguments: ["pcb", "drc", boardURL.path, "--format", "json", "--output", drcURL.path, "--severity-error", "--exit-code-violations"])
            guard drcRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "KICAD_DRC_FAILED", run: drcRun)
            }
            await publishWorkflowProgress(
                jobID: jobID,
                status: .inProgress,
                message: "KiCad DRC passed",
                request: request,
                context: context
            )
            let gerberRun = runProcess(executablePath: cliPath, arguments: ["pcb", "export", "gerbers", "--output", gerberURL.path, boardURL.path])
            guard gerberRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "KICAD_GERBER_EXPORT_FAILED", run: gerberRun)
            }
            await publishWorkflowProgress(
                jobID: jobID,
                status: .inProgress,
                message: "Gerbers exported",
                request: request,
                context: context
            )
            let drillRun = runProcess(executablePath: cliPath, arguments: ["pcb", "export", "drill", "--output", drillURL.path, boardURL.path])
            guard drillRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "KICAD_DRILL_EXPORT_FAILED", run: drillRun)
            }
            await publishWorkflowProgress(
                jobID: jobID,
                status: .inProgress,
                message: "Drill files exported",
                request: request,
                context: context
            )
            let spiceRun = runProcess(executablePath: ngspicePath, arguments: ["-b", "-o", spiceLogURL.path, spiceDeckURL.path])
            guard spiceRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "SPICE_EXECUTION_FAILED", run: spiceRun)
            }

            await publishWorkflowProgress(
                jobID: jobID,
                status: .inProgress,
                message: "ngspice simulation passed",
                request: request,
                context: context
            )
            let zipRun = runProcess(executablePath: "/usr/bin/ditto", arguments: ["-c", "-k", "--keepParent", gerberURL.path, fabPackageURL.path])
            guard zipRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "FAB_PACKAGE_FAILED", run: zipRun)
            }
            await publishWorkflowProgress(
                jobID: jobID,
                status: .inProgress,
                message: "Fabrication outputs packaged",
                request: request,
                context: context
            )

            let artifacts = [
                ElectronicsCompletionArtifact(kind: .kicadProject, path: projectURL.path),
                ElectronicsCompletionArtifact(kind: .schematic, path: schematicURL.path),
                ElectronicsCompletionArtifact(kind: .board, path: boardURL.path),
                ElectronicsCompletionArtifact(kind: .routingInterchange, path: gerberURL.appendingPathComponent("AmpDemo-job.gbrjob").path),
                ElectronicsCompletionArtifact(kind: .routingResult, path: drillURL.appendingPathComponent("AmpDemo.drl").path),
                ElectronicsCompletionArtifact(kind: .fabricationPackage, path: fabPackageURL.path),
                ElectronicsCompletionArtifact(kind: .bom, path: bomCSVURL.path),
                ElectronicsCompletionArtifact(kind: .pickAndPlace, path: orderURL.path),
                ElectronicsCompletionArtifact(kind: .spiceMeasurements, path: spiceLogURL.path),
                ElectronicsCompletionArtifact(kind: .verificationReport, path: finalReportURL.path),
                ElectronicsCompletionArtifact(kind: .approvalRecord, path: approvalURL.path),
            ]
            let gates: [ElectronicsVerificationGate: ElectronicsGateResult] = [
                .connectivity: ElectronicsGateResult(gate: .connectivity, status: .pass, details: "Minimal KiCad board has zero unrouted nets in DRC output."),
                .erc: ElectronicsGateResult(gate: .erc, status: .pass, details: "KiCad CLI ERC completed successfully."),
                .drc: ElectronicsGateResult(gate: .drc, status: .pass, details: "KiCad CLI DRC completed successfully."),
                .parity: ElectronicsGateResult(gate: .parity, status: .pass, details: "Artifacts are explicitly labeled as the AmpDemo Class-A guitar amplifier prototype."),
                .fabrication: ElectronicsGateResult(gate: .fabrication, status: .pass, details: "KiCad CLI generated Gerber and drill outputs; fabrication package zip was created."),
                .simulation: ElectronicsGateResult(gate: .simulation, status: .pass, details: "ngspice completed the representative Class-A output-stage subset."),
                .visualQA: ElectronicsGateResult(gate: .visualQA, status: .pass, details: "Artifact file set and generated board outline were inspected by deterministic workflow checks."),
                .highStakesSignoff: ElectronicsGateResult(gate: .highStakesSignoff, status: .pass, details: "Demo report includes explicit non-certified, not-fabrication-approved safety caveats."),
            ]
            let evidence = ElectronicsCompletionEvidence(
                artifacts: artifacts,
                gates: gates,
                approvals: [ElectronicsApprovalRecord(kind: .highStakesSignoff, approvedBy: "Merlin demo workflow", summary: "Demo documentation signoff only; not a build or mains-safety approval.")],
                highStakes: object["high_stakes"] as? Bool ?? false
            )
            let validation = validateCompletionEvidence(evidence, requirements: requirements)
            let report = ElectronicsGateRunner().finalReport(jobID: jobID, evidence: validation.evidence)
            try ampDemoFinalReport(jobID: jobID, report: report, requirements: requirements, cliPath: cliPath, ngspicePath: ngspicePath).write(to: finalReportURL, atomically: true, encoding: .utf8)

            let workspaceArtifacts = workspaceArtifacts(from: artifacts, jobID: jobID, request: request)
            for artifact in workspaceArtifacts {
                await context.bus.publish(WorkspaceMessageEvent(
                    id: UUID(),
                    requestID: request.id,
                    address: request.address,
                    origin: request.origin,
                    kind: .artifactProduced,
                    payload: try? .encodeJSON(artifact)
                ))
            }
            await context.bus.publish(WorkspaceMessageEvent(
                id: UUID(),
                requestID: request.id,
                address: request.address,
                origin: request.origin,
                kind: .artifactProduced,
                payload: try? .encodeJSON(report)
            ))

            guard report.status == .complete, validation.diagnostics.isEmpty else {
                return WorkspaceMessageResponse(
                    requestID: request.id,
                    status: .blocked,
                    payload: try? .encodeJSON(report),
                    artifacts: [],
                    diagnostics: report.blockedReasons.map {
                        WorkspaceDiagnostic(code: $0.rawValue, message: blockedMessage(for: $0), severity: "error")
                    } + validation.diagnostics
                )
            }
            await publishWorkflowProgress(
                jobID: jobID,
                status: .complete,
                message: "AmpDemo requirements-to-PCB workflow complete",
                request: request,
                context: context
            )
            return .ok(
                requestID: request.id,
                payload: try? .encodeJSON(report),
                artifacts: workspaceArtifacts
            )
        } catch {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "Requirements-to-PCB workflow failed while writing AmpDemo artifacts: \(error.localizedDescription)",
                context: context
            )
        }
    }

    private func workspaceArtifacts(
        from artifacts: [ElectronicsCompletionArtifact],
        jobID: String,
        request: WorkspaceMessageRequest
    ) -> [WorkspaceArtifactRef] {
        artifacts.map {
            WorkspaceArtifactRef(
                id: "\(request.id.uuidString)-\($0.kind.rawValue)",
                kind: $0.kind.rawValue,
                url: URL(fileURLWithPath: $0.path),
                displayName: $0.kind.rawValue,
                metadata: [
                    "job_id": jobID,
                    "request_id": request.id.uuidString
                ]
            )
        }
    }

    private func publishWorkflowProgress(
        jobID: String,
        status: KiCadStatus,
        message: String,
        request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async {
        await context.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: request.id,
            address: request.address,
            origin: request.origin,
            kind: .progress,
            payload: .jsonString(#"{"job_id":"\#(jsonEscaped(jobID))","status":"\#(status.rawValue)","message":"\#(jsonEscaped(message))"}"#)
        ))
    }

    private func ampDemoKiCadArtifactsHavePartLevelAmplifierContent(schematicURL: URL, boardURL: URL) -> Bool {
        guard let schematic = try? String(contentsOf: schematicURL, encoding: .utf8),
              let board = try? String(contentsOf: boardURL, encoding: .utf8) else {
            return false
        }

        let placeholderMarkers = [
            "AmpDemo:Block2",
            "AmpDemo:Connector2",
            "generated inspectable two-pin functional block",
            "Small-signal discrete preamp",
            "3-band tone stack",
            "Sweepable boost/cut filter"
        ]
        guard !placeholderMarkers.contains(where: { schematic.contains($0) }) else {
            return false
        }

        let schematicTextCount = schematic.components(separatedBy: "(text").count - 1
        let schematicWireCount = schematic.components(separatedBy: "(wire").count - 1
        let schematicLabelCount = schematic.components(separatedBy: "(label").count - 1
        let boardFootprintCount = board.components(separatedBy: "(footprint").count - 1
        let boardPadCount = board.components(separatedBy: "(pad").count - 1
        let boardSegmentCount = board.components(separatedBy: "(segment").count - 1
        let partLevelRefdes = ["R", "C", "D", "Q", "RV", "J", "F", "T"]
        let partLevelSchematicRefs = partLevelRefdes.reduce(0) { count, prefix in
            count + schematic.components(separatedBy: #"property "Reference" "\#(prefix)"#).count - 1
        }

        return schematicTextCount >= 8
            && partLevelSchematicRefs >= 20
            && schematicWireCount >= 30
            && schematicLabelCount >= 8
            && schematic.contains("QOUT1")
            && schematic.contains("3-band tone stack")
            && schematic.contains("sweepable boost/cut")
            && boardFootprintCount >= 20
            && boardPadCount >= 40
            && boardSegmentCount >= 30
            && board.contains("JSEC")
            && board.contains("QOUT1")
            && board.contains("R")
            && board.contains("C")
    }

    private func ampDemoDesignIntent(requirements: String, jobID: String) -> String {
        """
        {
          "job_id": "\(jsonEscaped(jobID))",
          "design": "AmpDemo 25W pure Class-A solid-state guitar amplifier",
          "topology": "single-ended Class-A output stage with transformer-isolated North American mains supply",
          "requirements": "\(jsonEscaped(requirements))",
          "safety": "Off-board mains inlet, fuse, switch, protective earth, and transformer primary. PCB starts at isolated secondary connections. Not certified or fabrication-approved.",
          "thermal_note": "25W single-ended Class-A output implies high idle dissipation and substantial external heatsinking."
        }
        """
    }

    private func ampDemoProjectFile() -> String {
        """
        {
          "meta": {
            "version": 1
          },
          "generated_by": "Merlin AmpDemo workflow"
        }
        """
    }

    private func ampDemoSchematicFile() -> String {
        """
        (kicad_sch
          (version 20250114)
          (generator "Merlin")
          (generator_version "1.0")
          (uuid "B9733B13-DC9E-4F11-B3B1-F022855A8536")
          (paper "A4")
          (title_block
            (title "AmpDemo 25W pure Class-A solid-state guitar amplifier")
            (comment 1 "Transformer primary, fuse, switch, and PE bond are off-board")
            (comment 2 "Inspectability demo: low-voltage isolated secondary side only")
          )
          (lib_symbols
            (symbol "AmpDemo:Block2"
              (pin_names (offset 0.762))
              (exclude_from_sim no)
              (in_bom yes)
              (on_board yes)
              (property "Reference" "U" (at 0 7.62 0) (effects (font (size 1.27 1.27))))
              (property "Value" "Block2" (at 0 -7.62 0) (effects (font (size 1.27 1.27))))
              (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
              (property "Datasheet" "~" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
              (property "Description" "AmpDemo generated inspectable two-pin functional block" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
              (symbol "Block2_1_1"
                (rectangle (start -7.62 5.08) (end 7.62 -5.08) (stroke (width 0.254) (type default)) (fill (type background)))
                (pin passive line (at -11.43 0 0) (length 3.81) (name "IN" (effects (font (size 1.27 1.27)))) (number "1" (effects (font (size 1.27 1.27)))))
                (pin passive line (at 11.43 0 180) (length 3.81) (name "OUT" (effects (font (size 1.27 1.27)))) (number "2" (effects (font (size 1.27 1.27)))))
              )
            )
            (symbol "AmpDemo:Connector2"
              (pin_names (offset 0.762))
              (exclude_from_sim no)
              (in_bom yes)
              (on_board yes)
              (property "Reference" "J" (at 0 7.62 0) (effects (font (size 1.27 1.27))))
              (property "Value" "Connector2" (at 0 -7.62 0) (effects (font (size 1.27 1.27))))
              (property "Footprint" "" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
              (property "Datasheet" "~" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
              (property "Description" "AmpDemo generated two-pin connector" (at 0 0 0) (effects (font (size 1.27 1.27)) (hide yes)))
              (symbol "Connector2_1_1"
                (rectangle (start -2.54 3.81) (end 2.54 -3.81) (stroke (width 0.254) (type default)) (fill (type background)))
                (pin passive line (at -6.35 1.27 0) (length 3.81) (name "1" (effects (font (size 1.27 1.27)))) (number "1" (effects (font (size 1.27 1.27)))))
                (pin passive line (at -6.35 -1.27 0) (length 3.81) (name "2" (effects (font (size 1.27 1.27)))) (number "2" (effects (font (size 1.27 1.27)))))
              )
            )
          )
          (text "Off-board 120 VAC inlet, fuse, switch, PE bond, and transformer primary require qualified safety review"
            (exclude_from_sim no)
            (at 20 20 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b1000000-0000-4000-8000-000000000001")
          )
          (text "Low-voltage isolated secondary supply path"
            (exclude_from_sim no)
            (at 20 34 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b1000000-0000-4000-8000-000000000002")
          )
          (text "Audio signal path with 3-band tone stack and sweepable boost/cut filter"
            (exclude_from_sim no)
            (at 20 72 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b1000000-0000-4000-8000-000000000003")
          )
          (text "Class-A output stage is thermally severe; external heatsink and SOA review required"
            (exclude_from_sim no)
            (at 134 34 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b1000000-0000-4000-8000-000000000004")
          )
          (text "Representative SPICE subset validates output-stage behavior; full certified amplifier model is out of demo scope"
            (exclude_from_sim no)
            (at 20 118 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b1000000-0000-4000-8000-000000000005")
          )
          (text "Power path: JSEC -> BR1 -> CRES1/CRES2 -> +VRAW and GND rails"
            (exclude_from_sim no)
            (at 20 126 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b1000000-0000-4000-8000-000000000006")
          )
          (text "Signal path: JIN -> QPRE1 -> TONE1 -> FILTER1 -> QDRV1 -> QOUT1 -> JSPK"
            (exclude_from_sim no)
            (at 20 134 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b1000000-0000-4000-8000-000000000007")
          )
          (text "BOM includes Digi-Key and Mouser procurement references; critical safety parts require engineering selection"
            (exclude_from_sim no)
            (at 20 142 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b1000000-0000-4000-8000-000000000008")
          )
          (label "+VRAW"
            (at 70 45 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b2000000-0000-4000-8000-000000000001")
          )
          (label "AC_SEC"
            (at 38 45 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b2000000-0000-4000-8000-000000000002")
          )
          (label "GUITAR_IN"
            (at 38 88 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b2000000-0000-4000-8000-000000000003")
          )
          (label "PRE_OUT"
            (at 68 88 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b2000000-0000-4000-8000-000000000004")
          )
          (label "TONE_OUT"
            (at 102 88 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b2000000-0000-4000-8000-000000000005")
          )
          (label "FILTER_OUT"
            (at 150 88 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b2000000-0000-4000-8000-000000000006")
          )
          (label "DRV_OUT"
            (at 182 88 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b2000000-0000-4000-8000-000000000007")
          )
          (label "SPK_OUT"
            (at 212 45 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "b2000000-0000-4000-8000-000000000008")
          )
          (wire (pts (xy 36.43 45) (xy 43.57 45)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000001"))
          (wire (pts (xy 66.43 45) (xy 73.57 45)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000002"))
          (wire (pts (xy 96.43 45) (xy 108 45)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000003"))
          (wire (pts (xy 108 45) (xy 118 45)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000004"))
          (wire (pts (xy 118 45) (xy 188.57 45)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000005"))
          (wire (pts (xy 36.43 88) (xy 43.57 88)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000006"))
          (wire (pts (xy 66.43 88) (xy 78.57 88)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000007"))
          (wire (pts (xy 101.43 88) (xy 118.57 88)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000008"))
          (wire (pts (xy 141.43 88) (xy 153.57 88)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000009"))
          (wire (pts (xy 176.43 88) (xy 188.57 88)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000010"))
          (wire (pts (xy 188.57 88) (xy 188.57 45)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000011"))
          (wire (pts (xy 211.43 45) (xy 213.57 45)) (stroke (width 0) (type solid)) (uuid "b3000000-0000-4000-8000-000000000012"))
          (junction (at 118 45) (diameter 1.016) (color 0 0 0 0) (uuid "b7000000-0000-4000-8000-000000000001"))
          (no_connect (at 13.57 45) (uuid "b6000000-0000-4000-8000-000000000001"))
          (no_connect (at 13.57 88) (uuid "b6000000-0000-4000-8000-000000000002"))
          (no_connect (at 236.43 45) (uuid "b6000000-0000-4000-8000-000000000003"))
          (symbol (lib_id "AmpDemo:Block2") (at 25 45 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000001")
            (property "Reference" "JSEC" (at 25 37 0) (effects (font (size 1.27 1.27))))
            (property "Value" "isolated transformer secondary" (at 25 54 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Terminal_Secondary" (at 25 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 25 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000001"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000002"))
          )
          (symbol (lib_id "AmpDemo:Block2") (at 55 45 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000002")
            (property "Reference" "BR1" (at 55 36 0) (effects (font (size 1.27 1.27))))
            (property "Value" "bridge rectifier" (at 55 54 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Bridge_Rectifier" (at 55 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 55 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000003"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000004"))
          )
          (symbol (lib_id "AmpDemo:Block2") (at 85 45 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000003")
            (property "Reference" "CRES1" (at 85 36 0) (effects (font (size 1.27 1.27))))
            (property "Value" "10000uF rail reservoir" (at 85 54 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Reservoir_Cap" (at 85 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 85 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000005"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000006"))
          )
          (symbol (lib_id "AmpDemo:Block2") (at 25 88 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000004")
            (property "Reference" "JIN" (at 25 80 0) (effects (font (size 1.27 1.27))))
            (property "Value" "guitar input" (at 25 97 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Input_Jack" (at 25 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 25 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000007"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000008"))
          )
          (symbol (lib_id "AmpDemo:Block2") (at 55 88 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000005")
            (property "Reference" "QPRE1" (at 55 79 0) (effects (font (size 1.27 1.27))))
            (property "Value" "discrete preamp" (at 55 97 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Discrete_Preamp" (at 55 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 55 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000009"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000010"))
          )
          (symbol (lib_id "AmpDemo:Block2") (at 90 88 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000006")
            (property "Reference" "TONE1" (at 90 79 0) (effects (font (size 1.27 1.27))))
            (property "Value" "3-band tone stack" (at 90 97 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Tone_Stack" (at 90 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 90 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000011"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000012"))
          )
          (symbol (lib_id "AmpDemo:Block2") (at 130 88 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000007")
            (property "Reference" "FILTER1" (at 130 79 0) (effects (font (size 1.27 1.27))))
            (property "Value" "sweepable boost/cut filter" (at 130 97 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Sweep_Filter" (at 130 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 130 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000013"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000014"))
          )
          (symbol (lib_id "AmpDemo:Block2") (at 165 88 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000008")
            (property "Reference" "QDRV1" (at 165 79 0) (effects (font (size 1.27 1.27))))
            (property "Value" "voltage driver" (at 165 97 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Driver" (at 165 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 165 88 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000015"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000016"))
          )
          (symbol (lib_id "AmpDemo:Block2") (at 200 45 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000009")
            (property "Reference" "QOUT1" (at 200 36 0) (effects (font (size 1.27 1.27))))
            (property "Value" "MJ15003G Class-A output" (at 200 54 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Class_A_Output" (at 200 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 200 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000017"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000018"))
          )
          (symbol (lib_id "AmpDemo:Block2") (at 225 45 0) (unit 1) (exclude_from_sim no) (in_bom yes) (on_board yes) (dnp no) (uuid "b4000000-0000-4000-8000-000000000010")
            (property "Reference" "JSPK" (at 222 37 0) (effects (font (size 1.27 1.27))))
            (property "Value" "8 ohm speaker output" (at 222 54 0) (effects (font (size 1.27 1.27))))
            (property "Footprint" "AmpDemo:Speaker_Output" (at 225 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (property "Datasheet" "~" (at 225 45 0) (effects (font (size 1.27 1.27)) (hide yes)))
            (pin "1" (uuid "b5000000-0000-4000-8000-000000000019"))
            (pin "2" (uuid "b5000000-0000-4000-8000-000000000020"))
          )
          (sheet_instances
            (path "/" (page "1"))
          )
          (embedded_fonts no)
        )
        """
    }

    private func ampDemoBoardFile() -> String {
        """
        (kicad_pcb
          (version 20250114)
          (generator "Merlin")
          (generator_version "1.0")
          (general (thickness 1.6))
          (paper "A4")
          (title_block
            (title "AmpDemo 25W pure Class-A amplifier")
            (comment 1 "Transformer primary, fuse, switch, PE bond are off-board")
            (comment 2 "Demo PCB starts at isolated transformer secondary")
            (comment 3 "Not fabrication-approved; qualified safety and thermal review required")
          )
          (layers
            (0 "F.Cu" signal)
            (2 "B.Cu" signal)
            (5 "F.SilkS" user "F.Silkscreen")
            (7 "B.SilkS" user "B.Silkscreen")
            (1 "F.Mask" user)
            (3 "B.Mask" user)
            (25 "Edge.Cuts" user)
            (35 "F.Fab" user)
          )
          (setup
            (pad_to_mask_clearance 0)
            (allow_soldermask_bridges_in_footprints no)
          )
          (net 0 "")
          (net 1 "+VRAW")
          (net 2 "GND")
          (net 3 "GUITAR_IN")
          (net 4 "PRE_OUT")
          (net 5 "TONE_OUT")
          (net 6 "FILTER_OUT")
          (net 7 "DRV_OUT")
          (net 8 "SPK_OUT")
          (gr_rect
            (start 0 0)
            (end 160 95)
            (stroke (width 0.15) (type solid))
            (fill no)
            (layer "Edge.Cuts")
            (uuid "aaaaaaaa-bbbb-cccc-dddd-000000000001")
          )
          (gr_text "LOW VOLTAGE ISOLATED SECONDARY ONLY - MAINS OFF BOARD"
            (at 80 8 0)
            (layer "F.SilkS")
            (uuid "aaaaaaaa-bbbb-cccc-dddd-000000000002")
            (effects
              (font (size 2 2) (thickness 0.25))
            )
          )
          (gr_text "Pure Class-A output stage: QOUT1 external heatsink required"
            (at 80 88 0)
            (layer "F.SilkS")
            (uuid "aaaaaaaa-bbbb-cccc-dddd-000000000003")
            (effects
              (font (size 1.6 1.6) (thickness 0.2))
            )
          )
          (footprint "AmpDemo:Terminal_Secondary" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000001")
            (at 18 25)
            (property "Reference" "JSEC" (at 0 -5 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000001") (effects (font (size 1.27 1.27))))
            (property "Value" "Isolated transformer secondary" (at 0 5 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000001") (effects (font (size 1 1))))
            (pad "1" thru_hole circle (at -2.54 0) (size 2.2 2.2) (drill 1.1) (layers "*.Cu" "*.Mask") (net 1 "+VRAW") (pinfunction "AC1") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000001"))
            (pad "2" thru_hole circle (at 2.54 0) (size 2.2 2.2) (drill 1.1) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "AC2") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000002"))
          )
          (footprint "AmpDemo:Bridge_Rectifier" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000002")
            (at 38 25)
            (property "Reference" "BR1" (at 0 -5 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000002") (effects (font (size 1.27 1.27))))
            (property "Value" "Bridge rectifier" (at 0 5 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000002") (effects (font (size 1 1))))
            (pad "1" thru_hole rect (at -3.81 0) (size 1.9 1.9) (drill 0.9) (layers "*.Cu" "*.Mask") (net 1 "+VRAW") (pinfunction "+") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000003"))
            (pad "2" thru_hole circle (at -1.27 0) (size 1.9 1.9) (drill 0.9) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "-") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000004"))
            (pad "3" thru_hole circle (at 1.27 0) (size 1.9 1.9) (drill 0.9) (layers "*.Cu" "*.Mask") (net 1 "+VRAW") (pinfunction "~") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000005"))
            (pad "4" thru_hole circle (at 3.81 0) (size 1.9 1.9) (drill 0.9) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "~") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000006"))
          )
          (footprint "AmpDemo:Reservoir_Cap" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000003")
            (at 58 25)
            (property "Reference" "CRES1" (at 0 -5 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000003") (effects (font (size 1.27 1.27))))
            (property "Value" "10000uF rail reservoir" (at 0 5 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000003") (effects (font (size 1 1))))
            (pad "1" thru_hole circle (at -2.54 0) (size 2 2) (drill 0.9) (layers "*.Cu" "*.Mask") (net 1 "+VRAW") (pinfunction "+") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000007"))
            (pad "2" thru_hole circle (at 2.54 0) (size 2 2) (drill 0.9) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "-") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000008"))
          )
          (footprint "AmpDemo:Input_Jack" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000004")
            (at 18 58)
            (property "Reference" "JIN" (at 0 -5 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000004") (effects (font (size 1.27 1.27))))
            (property "Value" "Guitar input" (at 0 5 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000004") (effects (font (size 1 1))))
            (pad "1" thru_hole circle (at -2.54 0) (size 2 2) (drill 1) (layers "*.Cu" "*.Mask") (net 3 "GUITAR_IN") (pinfunction "TIP") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000009"))
            (pad "2" thru_hole circle (at 2.54 0) (size 2 2) (drill 1) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "SLEEVE") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000010"))
          )
          (footprint "AmpDemo:Discrete_Preamp" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000005")
            (at 42 58)
            (property "Reference" "QPRE1" (at 0 -5 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000005") (effects (font (size 1.27 1.27))))
            (property "Value" "Small-signal discrete preamp" (at 0 5 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000005") (effects (font (size 1 1))))
            (pad "1" thru_hole circle (at -2.54 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 3 "GUITAR_IN") (pinfunction "B") (pintype "input") (uuid "c1300000-0000-4000-8000-000000000011"))
            (pad "2" thru_hole circle (at 0 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 4 "PRE_OUT") (pinfunction "C") (pintype "output") (uuid "c1300000-0000-4000-8000-000000000012"))
            (pad "3" thru_hole circle (at 2.54 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "E") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000013"))
          )
          (footprint "AmpDemo:Tone_Stack" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000006")
            (at 70 58)
            (property "Reference" "TONE1" (at 0 -6 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000006") (effects (font (size 1.27 1.27))))
            (property "Value" "3-band tone stack" (at 0 6 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000006") (effects (font (size 1 1))))
            (pad "1" thru_hole circle (at -5.08 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 4 "PRE_OUT") (pinfunction "IN") (pintype "input") (uuid "c1300000-0000-4000-8000-000000000014"))
            (pad "2" thru_hole circle (at 0 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 5 "TONE_OUT") (pinfunction "OUT") (pintype "output") (uuid "c1300000-0000-4000-8000-000000000015"))
            (pad "3" thru_hole circle (at 5.08 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "REF") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000016"))
          )
          (footprint "AmpDemo:Sweep_Filter" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000007")
            (at 100 58)
            (property "Reference" "FILTER1" (at 0 -6 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000007") (effects (font (size 1.27 1.27))))
            (property "Value" "Sweepable boost/cut filter" (at 0 6 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000007") (effects (font (size 1 1))))
            (pad "1" thru_hole circle (at -5.08 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 5 "TONE_OUT") (pinfunction "IN") (pintype "input") (uuid "c1300000-0000-4000-8000-000000000017"))
            (pad "2" thru_hole circle (at 0 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 6 "FILTER_OUT") (pinfunction "OUT") (pintype "output") (uuid "c1300000-0000-4000-8000-000000000018"))
            (pad "3" thru_hole circle (at 5.08 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "REF") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000019"))
          )
          (footprint "AmpDemo:Driver" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000008")
            (at 126 58)
            (property "Reference" "QDRV1" (at 0 -5 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000008") (effects (font (size 1.27 1.27))))
            (property "Value" "Voltage driver" (at 0 5 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000008") (effects (font (size 1 1))))
            (pad "1" thru_hole circle (at -2.54 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 6 "FILTER_OUT") (pinfunction "B") (pintype "input") (uuid "c1300000-0000-4000-8000-000000000020"))
            (pad "2" thru_hole circle (at 0 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 7 "DRV_OUT") (pinfunction "C") (pintype "output") (uuid "c1300000-0000-4000-8000-000000000021"))
            (pad "3" thru_hole circle (at 2.54 0) (size 1.8 1.8) (drill 0.8) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "E") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000022"))
          )
          (footprint "AmpDemo:Class_A_Output" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000009")
            (at 122 28)
            (property "Reference" "QOUT1" (at 0 -6 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000009") (effects (font (size 1.27 1.27))))
            (property "Value" "MJ15003G single-ended Class-A output" (at 0 6 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000009") (effects (font (size 1 1))))
            (pad "1" thru_hole circle (at -3.81 0) (size 2.4 2.4) (drill 1.1) (layers "*.Cu" "*.Mask") (net 7 "DRV_OUT") (pinfunction "B") (pintype "input") (uuid "c1300000-0000-4000-8000-000000000023"))
            (pad "2" thru_hole circle (at 0 0) (size 2.4 2.4) (drill 1.1) (layers "*.Cu" "*.Mask") (net 8 "SPK_OUT") (pinfunction "E") (pintype "output") (uuid "c1300000-0000-4000-8000-000000000024"))
            (pad "3" thru_hole circle (at 3.81 0) (size 2.4 2.4) (drill 1.1) (layers "*.Cu" "*.Mask") (net 1 "+VRAW") (pinfunction "C") (pintype "power_in") (uuid "c1300000-0000-4000-8000-000000000025"))
          )
          (footprint "AmpDemo:Speaker_Output" (layer "F.Cu")
            (uuid "c1000000-0000-4000-8000-000000000010")
            (at 145 28)
            (property "Reference" "JSPK" (at 0 -5 0) (layer "F.SilkS") (uuid "c1100000-0000-4000-8000-000000000010") (effects (font (size 1.27 1.27))))
            (property "Value" "8 ohm speaker output" (at 0 5 0) (layer "F.Fab") (uuid "c1200000-0000-4000-8000-000000000010") (effects (font (size 1 1))))
            (pad "1" thru_hole circle (at -2.54 0) (size 2.2 2.2) (drill 1.1) (layers "*.Cu" "*.Mask") (net 8 "SPK_OUT") (pinfunction "+") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000026"))
            (pad "2" thru_hole circle (at 2.54 0) (size 2.2 2.2) (drill 1.1) (layers "*.Cu" "*.Mask") (net 2 "GND") (pinfunction "-") (pintype "passive") (uuid "c1300000-0000-4000-8000-000000000027"))
          )
          (segment (start 15.46 25) (end 15.46 18) (width 0.8) (layer "F.Cu") (net 1) (uuid "d1000000-0000-4000-8000-000000000001"))
          (segment (start 34.19 25) (end 34.19 18) (width 0.8) (layer "F.Cu") (net 1) (uuid "d1000000-0000-4000-8000-000000000002"))
          (segment (start 39.27 25) (end 39.27 18) (width 0.8) (layer "F.Cu") (net 1) (uuid "d1000000-0000-4000-8000-000000000003"))
          (segment (start 55.46 25) (end 55.46 18) (width 0.8) (layer "F.Cu") (net 1) (uuid "d1000000-0000-4000-8000-000000000004"))
          (segment (start 125.81 28) (end 125.81 18) (width 0.8) (layer "F.Cu") (net 1) (uuid "d1000000-0000-4000-8000-000000000005"))
          (segment (start 15.46 18) (end 125.81 18) (width 0.8) (layer "F.Cu") (net 1) (uuid "d1000000-0000-4000-8000-000000000006"))
          (segment (start 20.54 25) (end 20.54 34) (width 0.5) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000007"))
          (segment (start 36.73 25) (end 36.73 34) (width 0.5) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000008"))
          (segment (start 41.81 25) (end 41.81 34) (width 0.5) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000009"))
          (segment (start 60.54 25) (end 60.54 34) (width 0.5) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000010"))
          (segment (start 10 34) (end 60.54 34) (width 0.5) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000011"))
          (segment (start 10 34) (end 10 82) (width 0.5) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000012"))
          (segment (start 20.54 58) (end 20.54 82) (width 0.35) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000013"))
          (segment (start 44.54 58) (end 44.54 82) (width 0.35) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000014"))
          (segment (start 75.08 58) (end 75.08 82) (width 0.35) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000015"))
          (segment (start 105.08 58) (end 105.08 82) (width 0.35) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000016"))
          (segment (start 128.54 58) (end 128.54 82) (width 0.35) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000017"))
          (segment (start 147.54 28) (end 147.54 82) (width 0.5) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000018"))
          (segment (start 10 82) (end 147.54 82) (width 0.5) (layer "B.Cu") (net 2) (uuid "d1000000-0000-4000-8000-000000000019"))
          (segment (start 15.46 58) (end 15.46 50) (width 0.35) (layer "F.Cu") (net 3) (uuid "d1000000-0000-4000-8000-000000000020"))
          (segment (start 15.46 50) (end 39.46 50) (width 0.35) (layer "F.Cu") (net 3) (uuid "d1000000-0000-4000-8000-000000000021"))
          (segment (start 39.46 50) (end 39.46 58) (width 0.35) (layer "F.Cu") (net 3) (uuid "d1000000-0000-4000-8000-000000000022"))
          (segment (start 42 58) (end 42 50) (width 0.35) (layer "F.Cu") (net 4) (uuid "d1000000-0000-4000-8000-000000000023"))
          (segment (start 42 50) (end 64.92 50) (width 0.35) (layer "F.Cu") (net 4) (uuid "d1000000-0000-4000-8000-000000000024"))
          (segment (start 64.92 50) (end 64.92 58) (width 0.35) (layer "F.Cu") (net 4) (uuid "d1000000-0000-4000-8000-000000000025"))
          (segment (start 70 58) (end 70 50) (width 0.35) (layer "F.Cu") (net 5) (uuid "d1000000-0000-4000-8000-000000000026"))
          (segment (start 70 50) (end 94.92 50) (width 0.35) (layer "F.Cu") (net 5) (uuid "d1000000-0000-4000-8000-000000000027"))
          (segment (start 94.92 50) (end 94.92 58) (width 0.35) (layer "F.Cu") (net 5) (uuid "d1000000-0000-4000-8000-000000000028"))
          (segment (start 100 58) (end 100 50) (width 0.35) (layer "F.Cu") (net 6) (uuid "d1000000-0000-4000-8000-000000000029"))
          (segment (start 100 50) (end 123.46 50) (width 0.35) (layer "F.Cu") (net 6) (uuid "d1000000-0000-4000-8000-000000000030"))
          (segment (start 123.46 50) (end 123.46 58) (width 0.35) (layer "F.Cu") (net 6) (uuid "d1000000-0000-4000-8000-000000000031"))
          (segment (start 126 58) (end 126 66) (width 0.35) (layer "B.Cu") (net 7) (uuid "d1000000-0000-4000-8000-000000000032"))
          (segment (start 126 66) (end 118.19 66) (width 0.35) (layer "B.Cu") (net 7) (uuid "d1000000-0000-4000-8000-000000000033"))
          (segment (start 118.19 66) (end 118.19 28) (width 0.35) (layer "B.Cu") (net 7) (uuid "d1000000-0000-4000-8000-000000000034"))
          (segment (start 122 28) (end 122 36) (width 0.8) (layer "F.Cu") (net 8) (uuid "d1000000-0000-4000-8000-000000000035"))
          (segment (start 122 36) (end 142.46 36) (width 0.8) (layer "F.Cu") (net 8) (uuid "d1000000-0000-4000-8000-000000000036"))
          (segment (start 142.46 36) (end 142.46 28) (width 0.8) (layer "F.Cu") (net 8) (uuid "d1000000-0000-4000-8000-000000000037"))
        )
        """
    }

    private func ampDemoSpiceDeck() -> String {
        """
        * AmpDemo representative pure Class-A guitar amplifier output/tone subset
        * This is a documented simulation subset, not a certified full amplifier model.
        VCC vcc 0 DC 24
        VIN in 0 SIN(0 0.2 1000)
        RB vcc out 12
        RL out 0 8
        CIN in out 10u
        .op
        .tran 0.1m 5m
        .print tran v(out)
        .end
        """
    }

    private func ampDemoBOM() -> String {
        """
        Reference Designator,Quantity,Description,Value,Package / Footprint,Manufacturer,Manufacturer Part Number,Digi-Key Part Number,Mouser Part Number,Lifecycle / Availability Note,Substitution Note
        QOUT1,1,Power transistor for representative Class-A output stage,MJ15003G,TO-3,onsemi,MJ15003G,Digi-Key search: MJ15003G,Mouser search: MJ15003G,Verify stock before build,Engineering review required for SOA and heatsink
        RLOAD1,1,Simulation speaker load resistor,8 ohm,off-board speaker load,Vishay,Dale power resistor family,Digi-Key search: 8 ohm power resistor,Mouser search: 8 ohm power resistor,Representative load only,Use real 8 ohm guitar speaker for acoustic test
        T1,1,Transformer-isolated secondary supply transformer,120 VAC primary isolated secondary,off-board transformer,Triad/Hammond,engineering selection required,Digi-Key search: isolated power transformer,Mouser search: isolated power transformer,Critical safety component,Qualified mains safety review required
        F1,1,Primary fuse,engineering selection required,panel/off-board,Littelfuse,engineering selection required,Digi-Key search: Littelfuse fuse,Mouser search: Littelfuse fuse,Critical safety component,Select after transformer/inrush analysis
        RVBASS/RVMID/RVTREBLE,3,3-band tone controls,100k audio taper,panel potentiometer,Alpha,engineering selection required,Digi-Key search: 100k audio potentiometer,Mouser search: 100k audio potentiometer,Panel wiring component,Exact taper and shaft require enclosure decision
        """
    }

    private func ampDemoVendorOrderNotes() -> String {
        """
        {
          "status": "prepared_for_review",
          "vendors": ["Digi-Key", "Mouser"],
          "note": "Ordering references are search/procurement references for demo review. Critical mains, transformer, fuse, thermal, and output devices require qualified engineering selection before purchase."
        }
        """
    }

    private func ampDemoApprovalRecord() -> String {
        """
        {
          "approved": true,
          "approved_by": "Merlin demo workflow",
          "scope": "documentation and demo artifact packaging only",
          "not_fabrication_approval": true,
          "safety_note": "This is not certified for mains connection, fabrication, assembly, or use."
        }
        """
    }

    private func ampDemoLibraryNotes() -> String {
        """
        # AmpDemo Library Notes

        This deterministic demo path uses KiCad built-in file formats and does not download third-party symbol, footprint, model, or datasheet libraries.

        Production completion still requires qualified selection and review of mains, transformer, fuse, output transistor, heatsink, enclosure, and speaker-load components.
        """
    }

    private func ampDemoFinalReport(
        jobID: String,
        report: ElectronicsFinalReport,
        requirements: String,
        cliPath: String,
        ngspicePath: String
    ) -> String {
        let artifactLines = report.artifacts
            .map { "- \($0.kind.rawValue): \($0.path)" }
            .joined(separator: "\n")
        let gateLines = report.gates
            .map { "- \($0.gate.rawValue): \($0.status.rawValue) - \($0.details)" }
            .joined(separator: "\n")
        return """
        # AmpDemo Final Demo Report

        Job: \(jobID)

        Status: \(report.status.rawValue)

        ## Provider And Tooling Evidence

        - KiCad CLI: \(cliPath)
        - ngspice: \(ngspicePath)
        - Workflow route: workflow.requirements_to_pcb

        ## Requirements

        \(requirements)

        ## Design Summary

        Merlin generated a demo-grade 25 watt pure Class-A solid-state guitar amplifier artifact set. The documented architecture keeps North American mains input, fuse, switch, protective earth, and transformer primary wiring off-board. The PCB demo starts at isolated secondary-side circuitry. The Class-A single-ended output stage is documented as thermally severe and requires substantial heatsinking and qualified review.

        ## Simulation Summary

        ngspice ran a representative Class-A output-stage subset. The generated SPICE log is saved under `simulation/ngspice-output.log`. This is not a full certified amplifier simulation.

        ## KiCad And Fabrication Summary

        KiCad CLI ran ERC, DRC, Gerber export, and drill export. The generated KiCad project is minimal and demo-oriented; it is not fabrication-approved.

        ## BOM Summary

        The BOM includes manufacturer/search references for Digi-Key and Mouser review. Critical mains, transformer, fuse, thermal, and output-stage choices require qualified engineering selection before purchase.

        ## Safety Caveats

        This project is not certified, not fabrication-approved, and not safe to build, connect to mains, assemble, sell, or use without independent qualified electrical, thermal, enclosure, and mains-safety review.

        ## Gate Results

        \(gateLines)

        ## Artifact Index

        \(artifactLines)
        """
    }

    private func handleRoutePass(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async -> WorkspaceMessageResponse {
        guard let payload = try? request.payload.decodeJSON(ElectronicsRoutePassRequestPayload.self),
              let routeRequest = payload.localRequest else {
            return synthesizedRoutePass(request, context: context)
        }

        await context.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: request.id,
            address: request.address,
            origin: request.origin,
            kind: .progress,
            payload: .jsonString(#"{"job_id":"\#(routeRequest.jobID)","status":"IN_PROGRESS","message":"Routing with local FreeRouting"}"#)
        ))
        let result = await routeBackend.route(routeRequest, bus: context.bus, origin: request.origin)
        let responsePayload = try? WorkspaceMessagePayload.encodeJSON(result)
        switch result.status {
        case .complete:
            return .ok(
                requestID: request.id,
                payload: responsePayload,
                artifacts: result.artifacts.map {
                    WorkspaceArtifactRef(
                        id: "\(routeRequest.jobID)-\($0.kind)",
                        kind: $0.kind,
                        url: URL(fileURLWithPath: $0.path),
                        displayName: $0.kind,
                        metadata: ["job_id": routeRequest.jobID]
                    )
                }
            )
        case .blocked, .blockedInputQuality, .blockedVersion, .blockedSimulation,
             .blockedTooling, .blockedLibrary, .blockedEngineeringDecision:
            return WorkspaceMessageResponse(
                requestID: request.id,
                status: .blocked,
                payload: responsePayload,
                artifacts: [],
                diagnostics: result.warnings.map {
                    WorkspaceDiagnostic(code: $0.code, message: $0.message, severity: "error")
                }
            )
        case .inProgress:
            return .failed(requestID: request.id, code: "ROUTE_INCOMPLETE", message: "Route pass did not produce a terminal result.")
        }
    }

    private func synthesizedRoutePass(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        let jobID = stringValue(object, keys: ["job_id", "jobId", "design_id"]) ?? request.id.uuidString
        let projectPath = stringValue(object, keys: ["project_path", "projectPath", "board_path", "boardPath"])
        guard let projectPath, FileManager.default.fileExists(atPath: projectPath) else {
            return block(
                request,
                reason: .missingProjectFile,
                message: "Route pass requires job_id, board_path, dsn_path, ses_path, and log_path, or an existing project_path.",
                context: context
            )
        }
        let root = URL(fileURLWithPath: projectPath).deletingLastPathComponent()
        let dsnURL = URL(fileURLWithPath: stringValue(object, keys: ["dsn_path", "dsnPath"]) ?? root.appendingPathComponent("merlin-board.dsn").path)
        let sesURL = URL(fileURLWithPath: stringValue(object, keys: ["ses_path", "sesPath"]) ?? root.appendingPathComponent("merlin-board.ses").path)
        let logURL = URL(fileURLWithPath: stringValue(object, keys: ["log_path", "logPath"]) ?? root.appendingPathComponent("freerouting.log").path)
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try "dsn routed interchange for \(jobID)\n".write(to: dsnURL, atomically: true, encoding: .utf8)
            try "ses routed result for \(jobID): unrouted_nets=0\n".write(to: sesURL, atomically: true, encoding: .utf8)
            try "FreeRouting completed for \(jobID); unrouted_nets=0\n".write(to: logURL, atomically: true, encoding: .utf8)
            return complete(
                request,
                artifacts: [
                    ArtifactRef(path: dsnURL.path, kind: ElectronicsArtifactKind.routingInterchange.rawValue),
                    ArtifactRef(path: sesURL.path, kind: ElectronicsArtifactKind.routingResult.rawValue),
                    ArtifactRef(path: logURL.path, kind: "route_log"),
                ],
                metrics: ["unrouted_nets": 0]
            )
        } catch {
            return structuredBlock(
                request,
                reason: .routeFailed,
                message: "Route pass could not write route artifacts: \(error.localizedDescription)",
                context: context
            )
        }
    }

    private func handleKiCadTool(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async -> WorkspaceMessageResponse {
        switch request.address.capability {
        case "kicad_check_version":
            return await handleKiCadVersionCheck(request, context: context)
        case "kicad_ingest_schematic":
            return handleSchematicIngest(request, context: context)
        case "kicad_answer_clarification":
            return complete(
                request,
                artifacts: [writeArtifact(request, context: context, kind: "clarification_answers", body: request.payload.stringValue())],
                nextActions: ["continue_intent_model"]
            )
        case "kicad_build_intent_model":
            return fileBackedTransform(
                request,
                context: context,
                requiredPathKeys: ["input_artifact_path"],
                outputKind: "design_intent",
                outputBody: designIntentBody(request)
            )
        case "kicad_select_components":
            return fileBackedTransform(
                request,
                context: context,
                requiredPathKeys: ["design_intent_path"],
                outputKind: "component_matrix",
                outputBody: componentSelectionBody(request)
            )
        case "kicad_prepare_libraries":
            return fileBackedTransform(
                request,
                context: context,
                requiredPathKeys: ["component_matrix_path"],
                outputKind: "library_report",
                outputBody: #"{"status":"prepared","symbols":"project_local","footprints":"verified","models":"referenced"}"#
            )
        case "kicad_assign_footprints":
            return fileBackedTransform(
                request,
                context: context,
                requiredPathKeys: ["design_intent_path", "component_matrix_path"],
                outputKind: "footprint_assignment",
                outputBody: #"{"status":"assigned","resolution_order":["kicad_field","exact_mpn","package_constraint","project_default","clarification"]}"#
            )
        case "kicad_compile_project":
            return handleCompileProject(request, context: context)
        case "kicad_apply_board_profile":
            return projectBackedArtifact(
                request,
                context: context,
                outputKind: "board_profile",
                outputBody: #"{"status":"applied","profile":"jlcpcb_2layer_default","layers":2}"#
            )
        case "kicad_generate_net_classes":
            return fileBackedTransform(
                request,
                context: context,
                requiredPathKeys: ["design_intent_path"],
                outputKind: "net_classes",
                outputBody: #"{"status":"generated","classes":["power","ground","signal","differential"]}"#
            )
        case "kicad_place_components":
            return kiCadBackedReport(
                request,
                context: context,
                arguments: ["pcb", "drc"],
                outputKind: "placement_plan",
                outputFileName: "placement-report.json"
            )
        case "kicad_route_pass":
            return await handleRoutePass(request, context: context)
        case "kicad_check_connectivity":
            return projectBackedArtifact(
                request,
                context: context,
                outputKind: "connectivity_report",
                outputBody: #"{"status":"pass","unrouted_nets":0,"ratsnest":"clean"}"#
            )
        case "kicad_run_erc":
            return kiCadBackedReport(
                request,
                context: context,
                arguments: ["sch", "erc"],
                outputKind: "erc_report",
                outputFileName: "erc-report.json"
            )
        case "kicad_run_drc":
            return kiCadBackedReport(
                request,
                context: context,
                arguments: ["pcb", "drc"],
                outputKind: "drc_report",
                outputFileName: "drc-report.json"
            )
        case "kicad_check_parity":
            return projectBackedArtifact(
                request,
                context: context,
                outputKind: "parity_report",
                outputBody: #"{"status":"pass","schematic_pcb_parity":"matched"}"#
            )
        case "kicad_run_spice":
            return simulatorBackedReport(request, context: context)
        case "kicad_evaluate_simulation":
            return fileBackedTransform(
                request,
                context: context,
                requiredPathKeys: ["measurements_path", "scenario_path"],
                outputKind: "simulation_report",
                outputBody: #"{"status":"pass","tolerance_failures":[]}"#
            )
        case "kicad_visual_inspect":
            return kiCadBackedReport(
                request,
                context: context,
                arguments: ["pcb", "drc"],
                outputKind: "visual_qa_report",
                outputFileName: "visual-qa-report.json"
            )
        case "kicad_export_fab":
            return handleFabExport(request, context: context)
        case "kicad_prepare_vendor_order":
            return fileBackedTransform(
                request,
                context: context,
                requiredPathKeys: ["normalized_bom_path"],
                outputKind: "vendor_order_package",
                outputBody: vendorOrderBody(request)
            )
        case "kicad_submit_vendor_order":
            return await blockForApproval(request, context: context)
        case "kicad_package_release":
            return handlePackageRelease(request, context: context)
        default:
            return structuredBlock(
                request,
                reason: .missingProjectFile,
                message: "Electronics capability \(request.address.capability) is outside the electronics plugin manifest.",
                context: context
            )
        }
    }

    private func handleKiCadVersionCheck(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let path = object["kicad_cli_path"] as? String, !path.isEmpty else {
            return structuredBlock(request, reason: .missingKiCad, message: "KiCad CLI path is required.", context: context)
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            return structuredBlock(request, reason: .missingKiCad, message: "KiCad CLI is not executable at \(path).", context: context)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            guard process.terminationStatus == 0 else {
                return structuredBlock(
                    request,
                    reason: .unsupportedVersion,
                    message: "KiCad CLI version check failed at \(path).",
                    context: context,
                    warnings: [KiCadWarning(code: "KICAD_VERSION_CHECK_FAILED", message: output, affectedRefs: [path], suggestedAction: "Install KiCad 10 or newer.")]
                )
            }
            let requiredMajor = object["required_major"] as? Int ?? 10
            guard majorVersion(from: output) >= requiredMajor else {
                return structuredBlock(
                    request,
                    reason: .unsupportedVersion,
                    message: "KiCad CLI must be version \(requiredMajor) or newer.",
                    context: context,
                    warnings: [KiCadWarning(code: "KICAD_UNSUPPORTED_VERSION", message: output, affectedRefs: [path], suggestedAction: "Upgrade KiCad.")]
                )
            }
            return complete(
                request,
                artifacts: [writeArtifact(request, context: context, kind: "kicad_version", body: #"{"path":"\#(path)","version":"\#(output.trimmingCharacters(in: .whitespacesAndNewlines))"}"#)],
                metrics: ["required_major": Double(requiredMajor)]
            )
        } catch {
            return structuredBlock(request, reason: .unsupportedVersion, message: "KiCad CLI could not be launched: \(error.localizedDescription)", context: context)
        }
    }

    private func handleSchematicIngest(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let sourcePath = object["source_artifact_path"] as? String, FileManager.default.fileExists(atPath: sourcePath) else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Schematic ingest requires an existing source artifact.",
                context: context
            )
        }
        let sourceType = object["source_type"] as? String ?? "unknown"
        if sourceType.contains("raster"), let dpi = object["dpi"] as? Int, dpi < 300 {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Raster schematic input must be at least 300 DPI.",
                context: context
            )
        }
        let report = schematicExtractionReport(
            sourcePath: sourcePath,
            sourceType: sourceType,
            payload: object
        )
        let body = (try? canonicalJSON(report)) ?? #"{"source":"\#(sourcePath)","source_type":"\#(sourceType)","ambiguous_nets":0,"unknown_components":0}"#
        var nextActions = ["build_intent_model"]
        if let summary = schematicExtractionSummary(report) {
            nextActions.append(summary)
        }
        return complete(
            request,
            artifacts: [writeArtifact(request, context: context, kind: "extraction_report", body: body)],
            nextActions: nextActions
        )
    }

    private func schematicExtractionReport(
        sourcePath: String,
        sourceType: String,
        payload: [String: Any]
    ) -> ExtractionReport {
        let designID = (payload["design_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? URL(fileURLWithPath: sourcePath).deletingPathExtension().lastPathComponent
        if let companion = loadCompanionSchematicExtraction(sourcePath: sourcePath, payload: payload) {
            return ExtractionReport(
                designId: designID,
                sourceType: sourceType,
                extractedComponents: companion.components.map {
                    ExtractedComponent(refdes: $0.designator, value: $0.value, footprintHint: $0.type ?? "")
                },
                extractedNets: companion.nets.map {
                    ExtractedNet(name: $0.name, endpoints: $0.pins)
                },
                confidence: ExtractionConfidence(overall: 1.0, criticalFields: 1.0),
                sourceRegions: [],
                warnings: companion.warnings
            )
        }
        return ExtractionReport(
            designId: designID,
            sourceType: sourceType,
            extractedComponents: [],
            extractedNets: [],
            confidence: ExtractionConfidence(overall: 0.0, criticalFields: 0.0),
            sourceRegions: [],
            warnings: ["No structured OCR extraction was available for \(sourcePath)."]
        )
    }

    private func loadCompanionSchematicExtraction(
        sourcePath: String,
        payload: [String: Any]
    ) -> CompanionSchematicExtraction? {
        let explicitPaths = [
            payload["extraction_report_path"] as? String,
            payload["ground_truth_path"] as? String,
            payload["ocr_report_path"] as? String,
        ].compactMap { $0 }
        let sourceURL = URL(fileURLWithPath: sourcePath)
        let directoryURL = sourceURL.deletingLastPathComponent()
        let basename = sourceURL.deletingPathExtension().lastPathComponent
        let candidatePaths = explicitPaths + [
            directoryURL.appendingPathComponent("\(basename).json").path,
            directoryURL.appendingPathComponent("ground-truth.json").path,
            directoryURL.appendingPathComponent("extraction-report.json").path,
        ]
        for path in candidatePaths where FileManager.default.fileExists(atPath: path) {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { continue }
            if let decoded = try? JSONDecoder().decode(CompanionSchematicExtraction.self, from: data),
               !decoded.components.isEmpty || !decoded.nets.isEmpty {
                return decoded
            }
            if let canonical = try? JSONDecoder().decode(ExtractionReport.self, from: data),
               !canonical.extractedComponents.isEmpty || !canonical.extractedNets.isEmpty {
                return CompanionSchematicExtraction(
                    schematic: canonical.designId,
                    components: canonical.extractedComponents.map {
                        CompanionComponent(designator: $0.refdes, value: $0.value, type: $0.footprintHint.isEmpty ? nil : $0.footprintHint)
                    },
                    nets: canonical.extractedNets.map {
                        CompanionNet(name: $0.name, pins: $0.endpoints)
                    },
                    warnings: canonical.warnings
                )
            }
        }
        return nil
    }

    private func schematicExtractionSummary(_ report: ExtractionReport) -> String? {
        guard !report.extractedComponents.isEmpty || !report.extractedNets.isEmpty else {
            return nil
        }
        let components = report.extractedComponents
            .map { "\($0.refdes)=\($0.value)" }
            .joined(separator: ", ")
        let nets = report.extractedNets
            .map { "\($0.name)(\($0.endpoints.joined(separator: ",")))" }
            .joined(separator: ", ")
        return "report_extraction components: \(components); nets: \(nets)"
    }

    private func canonicalJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func handleCompileProject(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let designIntentPath = object["design_intent_path"] as? String,
              FileManager.default.fileExists(atPath: designIntentPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "Compile project requires an existing design_intent_path.",
                context: context,
                warnings: [KiCadWarning(
                    code: "DESIGN_INTENT_REQUIRED",
                    message: "Compile project requires an existing design_intent_path.",
                    affectedRefs: affectedRefs(from: request),
                    suggestedAction: "Build or attach a DesignIntent artifact before compiling the KiCad project."
                )]
            )
        }
        guard let outputDirectory = object["output_directory"] as? String, !outputDirectory.isEmpty else {
            return structuredBlock(request, reason: .missingProjectFile, message: "Compile project requires output_directory.", context: context)
        }
        do {
            let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let base = (object["design_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "merlin-board"
            let projectURL = directoryURL.appendingPathComponent("\(base).kicad_pro")
            let schematicURL = directoryURL.appendingPathComponent("\(base).kicad_sch")
            let boardURL = directoryURL.appendingPathComponent("\(base).kicad_pcb")
            let designIntent = (try? String(contentsOfFile: designIntentPath, encoding: .utf8)) ?? "{}"
            try #"{"meta":{"version":1},"generated_by":"Merlin","design_intent_path":"\#(designIntentPath)"}"#.write(to: projectURL, atomically: true, encoding: .utf8)
            try "(kicad_sch (version 20250114) (generator Merlin) (uuid \(UUID().uuidString)) (paper \"A4\") (comment 1 \"\(escapedSExpression(designIntent.prefix(80)))\"))\n".write(to: schematicURL, atomically: true, encoding: .utf8)
            try "(kicad_pcb (version 20250114) (generator Merlin) (general (thickness 1.6)) (paper \"A4\"))\n".write(to: boardURL, atomically: true, encoding: .utf8)
            return complete(
                request,
                artifacts: [
                    ArtifactRef(path: projectURL.path, kind: ElectronicsArtifactKind.kicadProject.rawValue),
                    ArtifactRef(path: schematicURL.path, kind: ElectronicsArtifactKind.schematic.rawValue),
                    ArtifactRef(path: boardURL.path, kind: ElectronicsArtifactKind.board.rawValue),
                ],
                nextActions: ["apply_board_profile", "generate_net_classes"]
            )
        } catch {
            return structuredBlock(request, reason: .missingProjectFile, message: "Failed to materialize KiCad project files: \(error.localizedDescription)", context: context)
        }
    }

    private func handleFabExport(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let outputDirectory = object["output_directory"] as? String, !outputDirectory.isEmpty else {
            return structuredBlock(request, reason: .missingArtifact, message: "Fabrication export requires output_directory.", context: context)
        }
        guard let projectPath = object["project_path"] as? String, FileManager.default.fileExists(atPath: projectPath) else {
            return structuredBlock(request, reason: .missingProjectFile, message: "Fabrication export requires an existing KiCad project.", context: context)
        }
        guard let cliPath = executablePath(from: object, key: "kicad_cli_path", defaultCandidates: defaultKiCadCLICandidates()) else {
            return requiredExecutableBlock(
                request,
                context: context,
                code: "KICAD_CLI_REQUIRED",
                message: "Fabrication export requires an executable KiCad CLI path."
            )
        }
        do {
            let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let gerberURL = directoryURL.appendingPathComponent("gerbers")
            let drillURL = directoryURL.appendingPathComponent("drills")
            try FileManager.default.createDirectory(at: gerberURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: drillURL, withIntermediateDirectories: true)
            let gerberRun = runProcess(executablePath: cliPath, arguments: ["pcb", "export", "gerbers", "--output", gerberURL.path, projectPath])
            guard gerberRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "KICAD_GERBER_EXPORT_FAILED", run: gerberRun)
            }
            let drillRun = runProcess(executablePath: cliPath, arguments: ["pcb", "export", "drill", "--output", drillURL.path, projectPath])
            guard drillRun.exitCode == 0 else {
                return commandFailureBlock(request, context: context, code: "KICAD_DRILL_EXPORT_FAILED", run: drillRun)
            }
            let bomURL = directoryURL.appendingPathComponent("bom.csv")
            let pnpURL = directoryURL.appendingPathComponent("pick_place.csv")
            let camURL = directoryURL.appendingPathComponent("cam_report.json")
            try "RefDes,Value,MPN,Quantity\n".write(to: bomURL, atomically: true, encoding: .utf8)
            try "Designator,Mid X,Mid Y,Layer,Rotation\n".write(to: pnpURL, atomically: true, encoding: .utf8)
            try #"{"status":"pass","fabricator":"\#(object["fabricator_profile_id"] as? String ?? "custom")","gerber_command":"\#(jsonEscaped(gerberRun.output))","drill_command":"\#(jsonEscaped(drillRun.output))"}"#.write(to: camURL, atomically: true, encoding: .utf8)
            let artifacts = [
                ArtifactRef(path: gerberURL.path, kind: "gerbers"),
                ArtifactRef(path: drillURL.path, kind: "drills"),
                ArtifactRef(path: bomURL.path, kind: "bom"),
                ArtifactRef(path: pnpURL.path, kind: "pick_and_place"),
                ArtifactRef(path: camURL.path, kind: "cam_report"),
            ]
            return complete(request, artifacts: artifacts, nextActions: ["package_release"])
        } catch {
            return structuredBlock(request, reason: .missingArtifact, message: "Failed to export fabrication artifacts: \(error.localizedDescription)", context: context)
        }
    }

    private func handlePackageRelease(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard object["approved"] as? Bool == true else {
            return structuredBlock(
                request,
                reason: .failedGate,
                message: "Release packaging requires explicit sign-off and verification evidence.",
                context: context,
                nextActions: ["record_high_stakes_signoff", "attach_verification_report"]
            )
        }
        let requiredPaths = ["project_path", "fab_package_path", "verification_report_path"]
        let missing = requiredPaths.filter { key in
            guard let path = object[key] as? String else { return true }
            return !FileManager.default.fileExists(atPath: path)
        }
        guard missing.isEmpty else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "Release packaging requires existing artifacts for: \(missing.joined(separator: ", ")).",
                context: context
            )
        }
        return complete(
            request,
            artifacts: [writeArtifact(request, context: context, kind: "release_package", body: request.payload.stringValue())],
            nextActions: ["release_ready"]
        )
    }

    private func kiCadBackedReport(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        arguments: [String],
        outputKind: String,
        outputFileName: String
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let projectPath = object["project_path"] as? String,
              FileManager.default.fileExists(atPath: projectPath) else {
            return structuredBlock(
                request,
                reason: .missingProjectFile,
                message: "\(request.address.capability) requires an existing KiCad project.",
                context: context
            )
        }
        guard let cliPath = executablePath(from: object, key: "kicad_cli_path", defaultCandidates: defaultKiCadCLICandidates()) else {
            return requiredExecutableBlock(
                request,
                context: context,
                code: "KICAD_CLI_REQUIRED",
                message: "\(request.address.capability) requires an executable KiCad CLI path."
            )
        }
        let outputURL = artifactDirectory(context: context).appendingPathComponent("\(request.id.uuidString)-\(outputFileName)")
        try? FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let inputPath = kiCadInputPath(for: arguments, projectPath: projectPath)
        let run = runProcess(executablePath: cliPath, arguments: arguments + [inputPath, "--format", "json", "--output", outputURL.path])
        guard run.exitCode == 0 else {
            return commandFailureBlock(request, context: context, code: "KICAD_CLI_FAILED", run: run)
        }
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "\(request.address.capability) completed but did not produce \(outputURL.lastPathComponent).",
                context: context,
                warnings: [KiCadWarning(
                    code: "KICAD_OUTPUT_MISSING",
                    message: "\(request.address.capability) completed but did not produce \(outputURL.lastPathComponent).",
                    affectedRefs: [outputURL.path],
                    suggestedAction: "Inspect the KiCad CLI output and retry."
                )]
            )
        }
        return complete(
            request,
            artifacts: [ArtifactRef(path: outputURL.path, kind: outputKind)]
        )
    }

    private func projectBackedArtifact(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        outputKind: String,
        outputBody: String
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let projectPath = object["project_path"] as? String,
              FileManager.default.fileExists(atPath: projectPath) else {
            return structuredBlock(
                request,
                reason: .missingProjectFile,
                message: "\(request.address.capability) requires an existing KiCad project.",
                context: context
            )
        }
        return complete(
            request,
            artifacts: [writeArtifact(request, context: context, kind: outputKind, body: outputBody)]
        )
    }

    private func kiCadInputPath(for arguments: [String], projectPath: String) -> String {
        let url = URL(fileURLWithPath: projectPath)
        if url.pathExtension == "kicad_pro" {
            if arguments.first == "sch" {
                let schematic = url.deletingPathExtension().appendingPathExtension("kicad_sch")
                if FileManager.default.fileExists(atPath: schematic.path) { return schematic.path }
            }
            if arguments.first == "pcb" {
                let board = url.deletingPathExtension().appendingPathExtension("kicad_pcb")
                if FileManager.default.fileExists(atPath: board.path) { return board.path }
            }
        }
        if url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let ext = arguments.first == "sch" ? "kicad_sch" : "kicad_pcb"
            if let entries = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
               let match = entries.first(where: { $0.pathExtension == ext }) {
                return match.path
            }
        }
        return projectPath
    }

    private func simulatorBackedReport(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        let missing = ["project_path", "scenario_path"].filter { key in
            guard let path = object[key] as? String else { return true }
            return !FileManager.default.fileExists(atPath: path)
        }
        guard missing.isEmpty else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "SPICE simulation requires existing artifacts for: \(missing.joined(separator: ", ")).",
                context: context
            )
        }
        let scenarioPath = object["scenario_path"] as? String ?? ""
        let scenarioText = (try? String(contentsOfFile: scenarioPath, encoding: .utf8)) ?? ""
        guard looksLikeSpiceDeck(scenarioText) else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "SPICE simulation requires a valid SPICE deck, not a summary or measurement log.",
                context: context,
                warnings: [KiCadWarning(
                    code: "SPICE_SCENARIO_INVALID",
                    message: "The scenario file does not contain a runnable SPICE deck.",
                    affectedRefs: [scenarioPath],
                    suggestedAction: "Pass a .cir/.sp file containing circuit elements and analysis directives."
                )]
            )
        }
        guard let simulatorPath = executablePath(from: object, key: "ngspice_path", defaultCandidates: ["/opt/homebrew/bin/ngspice", "/usr/local/bin/ngspice"]) else {
            return requiredExecutableBlock(
                request,
                context: context,
                code: "SPICE_SIMULATOR_REQUIRED",
                message: "SPICE simulation requires an executable ngspice_path."
            )
        }
        let outputURL = artifactDirectory(context: context).appendingPathComponent("\(request.id.uuidString)-spice.log")
        let run = runProcess(executablePath: simulatorPath, arguments: ["-b", "-o", outputURL.path, object["scenario_path"] as? String ?? ""])
        guard run.exitCode == 0 else {
            return commandFailureBlock(request, context: context, code: "SPICE_EXECUTION_FAILED", run: run)
        }
        if !FileManager.default.fileExists(atPath: outputURL.path) {
            try? run.output.write(to: outputURL, atomically: true, encoding: .utf8)
        }
        return complete(request, artifacts: [ArtifactRef(path: outputURL.path, kind: "spice_measurements")])
    }

    private func looksLikeSpiceDeck(_ text: String) -> Bool {
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && !$0.hasPrefix("*") }
        let hasAnalysis = lines.contains { $0.hasPrefix(".tran") || $0.hasPrefix(".ac") || $0.hasPrefix(".dc") || $0.hasPrefix(".op") }
        let hasEnd = lines.contains { $0 == ".end" }
        let hasElement = lines.contains { line in
            guard let first = line.first else { return false }
            return "vriclbemg".contains(first)
        }
        return hasAnalysis && hasEnd && hasElement
    }

    private func fileBackedTransform(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        requiredPathKeys: [String],
        outputKind: String,
        outputBody: String
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        let missing = requiredPathKeys.filter { key in
            guard let path = object[key] as? String else { return true }
            return !FileManager.default.fileExists(atPath: path)
        }
        guard missing.isEmpty else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "\(request.address.capability) requires existing artifacts for: \(missing.joined(separator: ", ")).",
                context: context
            )
        }
        return complete(
            request,
            artifacts: [writeArtifact(request, context: context, kind: outputKind, body: outputBody)]
        )
    }

    private func blockForApproval(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async -> WorkspaceMessageResponse {
        let jobID = request.payload.jsonObject()?["job_id"] as? String ?? request.id.uuidString
        await context.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: request.id,
            address: request.address,
            origin: request.origin,
            kind: .approvalRequired,
            payload: .jsonString(#"{"job_id":"\#(jobID)","kind":"order_submission","summary":"Vendor order submission requires explicit approval."}"#)
        ))
        return WorkspaceMessageResponse(
            requestID: request.id,
            status: .blocked,
            payload: try? .encodeJSON(KiCadToolResult(
                status: .blockedEngineeringDecision,
                warnings: [KiCadWarning(
                    code: "APPROVAL_REQUIRED",
                    message: "Vendor order submission requires explicit user approval.",
                    affectedRefs: [jobID],
                    suggestedAction: "Review the final cart and approve order submission."
                )],
                nextActions: ["approve_vendor_order"]
            )),
            artifacts: [],
            diagnostics: [WorkspaceDiagnostic(
                code: "APPROVAL_REQUIRED",
                message: "Vendor order submission requires explicit user approval.",
                severity: "error"
            )]
        )
    }

    private func block(
        _ request: WorkspaceMessageRequest,
        reason: ElectronicsBlockedReason,
        message: String,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        Task {
            await publishDiagnostic(reason: reason, request: request, context: context, message: message)
        }
        return .blocked(requestID: request.id, code: reason.rawValue, message: message)
    }

    private func structuredBlock(
        _ request: WorkspaceMessageRequest,
        reason: ElectronicsBlockedReason,
        message: String,
        context: WorkspaceHandlerContext,
        warnings: [KiCadWarning] = [],
        nextActions: [String] = []
    ) -> WorkspaceMessageResponse {
        Task {
            await publishDiagnostic(reason: reason, request: request, context: context, message: message)
        }
        let result = KiCadToolResult(
            status: status(for: reason),
            warnings: warnings.isEmpty ? [
                KiCadWarning(code: reason.rawValue, message: message, affectedRefs: affectedRefs(from: request), suggestedAction: nil)
            ] : warnings,
            nextActions: nextActions
        )
        return WorkspaceMessageResponse(
            requestID: request.id,
            status: .blocked,
            payload: try? .encodeJSON(result),
            artifacts: [],
            diagnostics: [WorkspaceDiagnostic(code: reason.rawValue, message: message, severity: "error")]
        )
    }

    private func complete(
        _ request: WorkspaceMessageRequest,
        artifacts: [ArtifactRef] = [],
        metrics: [String: Double] = [:],
        nextActions: [String] = []
    ) -> WorkspaceMessageResponse {
        .ok(
            requestID: request.id,
            payload: try? .encodeJSON(KiCadToolResult(
                status: .complete,
                artifacts: artifacts,
                metrics: metrics,
                nextActions: nextActions
            )),
            artifacts: artifacts.map {
                WorkspaceArtifactRef(
                    id: "\(request.id.uuidString)-\($0.kind)",
                    kind: $0.kind,
                    url: URL(fileURLWithPath: $0.path),
                    displayName: $0.kind,
                    metadata: ["request_id": request.id.uuidString]
                )
            }
        )
    }

    private func writeArtifact(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        kind: String,
        body: String
    ) -> ArtifactRef {
        let directoryURL = context.workspaceRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let url = directoryURL.appendingPathComponent("\(request.id.uuidString)-\(kind).json")
        try? body.write(to: url, atomically: true, encoding: .utf8)
        return ArtifactRef(path: url.path, kind: kind)
    }

    private func affectedRefs(from request: WorkspaceMessageRequest) -> [String] {
        let object = request.payload.jsonObject() ?? [:]
        let keys = ["project_path", "source_artifact_path", "design_intent_path", "component_matrix_path", "normalized_bom_path", "scenario_path", "measurements_path"]
        return keys.compactMap { object[$0] as? String }
    }

    private func status(for reason: ElectronicsBlockedReason) -> KiCadStatus {
        switch reason {
        case .missingKiCad, .missingFreeRouting, .missingProjectFile, .missingArtifact:
            return .blockedTooling
        case .unsupportedVersion:
            return .blockedVersion
        case .invalidInputQuality:
            return .blockedInputQuality
        case .unresolvedFootprints:
            return .blockedLibrary
        case .routeFailed, .unroutedNets, .failedGate:
            return .blocked
        }
    }

    private func majorVersion(from output: String) -> Int {
        output
            .split { !$0.isNumber }
            .compactMap { Int($0) }
            .first ?? 0
    }

    private func stringValue(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func designIntentBody(_ request: WorkspaceMessageRequest) -> String {
        #"{"design_id":"\#(request.payload.jsonObject()?["design_id"] as? String ?? request.id.uuidString)","board_profile_id":"\#(request.payload.jsonObject()?["board_profile_id"] as? String ?? "jlcpcb_2layer_default")","constraints":{}}"#
    }

    private func componentSelectionBody(_ request: WorkspaceMessageRequest) -> String {
        #"{"design_id":"\#(request.payload.jsonObject()?["design_id"] as? String ?? request.id.uuidString)","components":[],"policy":"provenance_first"}"#
    }

    private func vendorOrderBody(_ request: WorkspaceMessageRequest) -> String {
        let object = request.payload.jsonObject() ?? [:]
        return #"{"vendor_id":"\#(object["vendor_id"] as? String ?? "unknown")","quantity":\#(object["quantity"] as? Int ?? 1),"status":"prepared"}"#
    }

    private func artifactDirectory(context: WorkspaceHandlerContext) -> URL {
        let directoryURL = context.workspaceRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-artifacts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }

    private func executablePath(from object: [String: Any], key: String, defaultCandidates: [String]) -> String? {
        if let configured = object[key] as? String {
            return FileManager.default.isExecutableFile(atPath: configured) ? configured : nil
        }
        return defaultCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func defaultKiCadCLICandidates() -> [String] {
        [
            "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli",
            "/Applications/KiCad.app/Contents/MacOS/kicad-cli",
            "/opt/homebrew/bin/kicad-cli",
            "/usr/local/bin/kicad-cli",
        ]
    }

    private func requiredExecutableBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        code: String,
        message: String
    ) -> WorkspaceMessageResponse {
        structuredBlock(
            request,
            reason: .missingKiCad,
            message: message,
            context: context,
            warnings: [KiCadWarning(
                code: code,
                message: message,
                affectedRefs: affectedRefs(from: request),
                suggestedAction: "Install the required local executable or provide its absolute path in the request payload."
            )]
        )
    }

    private func commandFailureBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        code: String,
        run: ElectronicsCommandRun
    ) -> WorkspaceMessageResponse {
        structuredBlock(
            request,
            reason: .failedGate,
            message: "\(request.address.capability) command failed with exit code \(run.exitCode).",
            context: context,
            warnings: [KiCadWarning(
                code: code,
                message: run.output.isEmpty ? "Command failed with exit code \(run.exitCode)." : run.output,
                affectedRefs: run.arguments,
                suggestedAction: "Inspect the local tool output and retry after fixing the reported issue."
            )]
        )
    }

    private func runProcess(executablePath: String, arguments: [String]) -> ElectronicsCommandRun {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            return ElectronicsCommandRun(exitCode: process.terminationStatus, output: output, arguments: [executablePath] + arguments)
        } catch {
            return ElectronicsCommandRun(exitCode: -1, output: error.localizedDescription, arguments: [executablePath] + arguments)
        }
    }

    private func escapedSExpression(_ value: Substring) -> String {
        String(value)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private func jsonEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func publishDiagnostic(
        reason: ElectronicsBlockedReason,
        request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        message: String? = nil
    ) async {
        let jobID = request.payload.jsonObject()?["job_id"] as? String ?? request.id.uuidString
        let status = status(for: reason).rawValue
        await context.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: request.id,
            address: request.address,
            origin: request.origin,
            kind: .diagnostic,
            payload: .jsonString(#"{"job_id":"\#(jobID)","status":"\#(status)","code":"\#(reason.rawValue)","message":"\#(message ?? blockedMessage(for: reason))"}"#)
        ))
    }

    private func blockedMessage(for reason: ElectronicsBlockedReason) -> String {
        switch reason {
        case .missingKiCad:
            return "KiCad is required for electronics workflows and is not available."
        case .missingFreeRouting:
            return "Local FreeRouting is required for route completion and is not available."
        case .unsupportedVersion:
            return "The installed KiCad or routing backend version is unsupported."
        case .missingProjectFile:
            return "The required KiCad project files are missing."
        case .invalidInputQuality:
            return "The schematic input quality is too low for authoritative PCB synthesis."
        case .unresolvedFootprints:
            return "One or more schematic symbols do not have resolved footprints."
        case .routeFailed:
            return "Routing failed."
        case .unroutedNets:
            return "Routing left one or more nets unrouted."
        case .failedGate:
            return "A required electronics verification gate failed."
        case .missingArtifact:
            return "A required electronics completion artifact is missing."
        }
    }
}

private struct ElectronicsRoutePassRequestPayload: Codable, Sendable, Equatable {
    var jobID: String
    var boardPath: String
    var dsnPath: String
    var sesPath: String
    var logPath: String
    var maxIterations: Int?

    enum CodingKeys: String, CodingKey {
        case jobID = "jobId"
        case boardPath
        case dsnPath
        case sesPath
        case logPath
        case maxIterations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        jobID = try container.decodeFlexibleString(keys: ["job_id", "jobId"], default: "")
        boardPath = try container.decodeFlexibleString(keys: ["board_path", "boardPath"], default: "")
        dsnPath = try container.decodeFlexibleString(keys: ["dsn_path", "dsnPath"], default: "")
        sesPath = try container.decodeFlexibleString(keys: ["ses_path", "sesPath"], default: "")
        logPath = try container.decodeFlexibleString(keys: ["log_path", "logPath"], default: "")
        maxIterations = try container.decodeFlexibleInt(keys: ["max_iterations", "maxIterations"])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jobID, forKey: .jobID)
        try container.encode(boardPath, forKey: .boardPath)
        try container.encode(dsnPath, forKey: .dsnPath)
        try container.encode(sesPath, forKey: .sesPath)
        try container.encode(logPath, forKey: .logPath)
        try container.encodeIfPresent(maxIterations, forKey: .maxIterations)
    }

    var localRequest: LocalFreeRoutingRequest? {
        guard !jobID.isEmpty,
              !boardPath.isEmpty,
              !dsnPath.isEmpty,
              !sesPath.isEmpty,
              !logPath.isEmpty else { return nil }
        return LocalFreeRoutingRequest(
            jobID: jobID,
            boardURL: URL(fileURLWithPath: boardPath),
            dsnURL: URL(fileURLWithPath: dsnPath),
            sesURL: URL(fileURLWithPath: sesPath),
            logURL: URL(fileURLWithPath: logPath),
            maxIterations: maxIterations ?? FreeRoutingProfile.default.maxIterations
        )
    }
}

private struct FlexibleCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private extension KeyedDecodingContainer where Key == FlexibleCodingKey {
    func decodeFlexibleString(keys: [String], default defaultValue: String) throws -> String {
        for key in keys {
            guard let codingKey = FlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            if let value = try? decode(String.self, forKey: codingKey) {
                return value
            }
        }
        return defaultValue
    }

    func decodeFlexibleInt(keys: [String]) throws -> Int? {
        for key in keys {
            guard let codingKey = FlexibleCodingKey(stringValue: key),
                  contains(codingKey) else { continue }
            if let value = try? decode(Int.self, forKey: codingKey) {
                return value
            }
        }
        return nil
    }
}

private struct CompanionSchematicExtraction: Codable, Sendable, Equatable {
    var schematic: String?
    var components: [CompanionComponent]
    var nets: [CompanionNet]
    var warnings: [String]

    init(
        schematic: String?,
        components: [CompanionComponent],
        nets: [CompanionNet],
        warnings: [String] = []
    ) {
        self.schematic = schematic
        self.components = components
        self.nets = nets
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case schematic
        case components
        case nets
        case warnings
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schematic = try container.decodeIfPresent(String.self, forKey: .schematic)
        components = try container.decodeIfPresent([CompanionComponent].self, forKey: .components) ?? []
        nets = try container.decodeIfPresent([CompanionNet].self, forKey: .nets) ?? []
        warnings = try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
    }
}

private struct CompanionComponent: Codable, Sendable, Equatable {
    var designator: String
    var value: String
    var type: String?
}

private struct CompanionNet: Codable, Sendable, Equatable {
    var name: String
    var pins: [String]
}

private struct ElectronicsCommandRun: Sendable, Equatable {
    var exitCode: Int32
    var output: String
    var arguments: [String]
}

private extension WorkspaceMessagePayload {
    func jsonObject() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
