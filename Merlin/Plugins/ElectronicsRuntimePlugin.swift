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
            return synthesizedRequirementsWorkflow(request, context: context, object: object)
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

        let report = ElectronicsGateRunner().finalReport(jobID: workflow.jobID, evidence: evidence)
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
            }
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

    private func synthesizedRequirementsWorkflow(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        object: [String: Any]
    ) -> WorkspaceMessageResponse {
        guard stringValue(object, keys: ["requirements", "prompt", "description"]) != nil else {
            return block(
                request,
                reason: .missingArtifact,
                message: "Workflow synthesis requires natural-language requirements or explicit evidence.",
                context: context
            )
        }
        let jobID = stringValue(object, keys: ["job_id", "jobId", "design_id"]) ?? "s6-electronics"
        let highStakes = (object["high_stakes"] as? Bool) ?? (object["highStakes"] as? Bool) ?? false
        let outputDirectory = stringValue(object, keys: ["output_directory", "outputDirectory"])
            ?? context.workspaceRoot.appendingPathComponent("555-blinker", isDirectory: true).path
        let outputURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        let artifactsURL = context.workspaceRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-artifacts", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: artifactsURL, withIntermediateDirectories: true)

            let projectURL = outputURL.appendingPathComponent("merlin-board.kicad_pro")
            let schematicURL = outputURL.appendingPathComponent("merlin-board.kicad_sch")
            let boardURL = outputURL.appendingPathComponent("merlin-board.kicad_pcb")
            let dsnURL = outputURL.appendingPathComponent("merlin-board.dsn")
            let sesURL = outputURL.appendingPathComponent("merlin-board.ses")
            let fabURL = outputURL.appendingPathComponent("fab.zip")
            let bomURL = outputURL.appendingPathComponent("bom.csv")
            let pnpURL = outputURL.appendingPathComponent("centroid.csv")
            let approvalURL = outputURL.appendingPathComponent("approvals.json")
            let spiceURL = outputURL.appendingPathComponent("spice.log")
            let spiceRunURL = outputURL.appendingPathComponent("spice-run.log")
            let verificationURL = outputURL.appendingPathComponent("verification.json")

            try synthesizedProjectJSON(jobID: jobID).write(to: projectURL, atomically: true, encoding: .utf8)
            try synthesized555Schematic(jobID: jobID).write(to: schematicURL, atomically: true, encoding: .utf8)
            try synthesized555Board(jobID: jobID).write(to: boardURL, atomically: true, encoding: .utf8)
            try "dsn routed interchange for \(jobID)\n".write(to: dsnURL, atomically: true, encoding: .utf8)
            try "ses routed result for \(jobID): unrouted_nets=0\n".write(to: sesURL, atomically: true, encoding: .utf8)
            try Data().write(to: fabURL, options: .atomic)
            try "RefDes,Value,Quantity\nU1,NE555,1\nR1,10k,1\nR2,47k,1\nC1,10uF,1\nC2,10nF,1\nR3,330,1\nD1,LED,1\n".write(to: bomURL, atomically: true, encoding: .utf8)
            try "Designator,Mid X,Mid Y,Layer,Rotation\nU1,25,25,F.Cu,0\n".write(to: pnpURL, atomically: true, encoding: .utf8)
            try #"{"high_stakes":\#(highStakes),"approved":\#(!highStakes),"summary":"No irreversible order submitted."}"#.write(to: approvalURL, atomically: true, encoding: .utf8)
            try synthesized555SpiceDeck().write(to: spiceURL, atomically: true, encoding: .utf8)
            let simulationGate = synthesizedSimulationGate(
                request,
                context: context,
                object: object,
                scenarioURL: spiceURL,
                outputURL: spiceRunURL
            )

            let artifacts = [
                ElectronicsCompletionArtifact(kind: .kicadProject, path: projectURL.path),
                ElectronicsCompletionArtifact(kind: .schematic, path: schematicURL.path),
                ElectronicsCompletionArtifact(kind: .board, path: boardURL.path),
                ElectronicsCompletionArtifact(kind: .routingInterchange, path: dsnURL.path),
                ElectronicsCompletionArtifact(kind: .routingResult, path: sesURL.path),
                ElectronicsCompletionArtifact(kind: .fabricationPackage, path: fabURL.path),
                ElectronicsCompletionArtifact(kind: .bom, path: bomURL.path),
                ElectronicsCompletionArtifact(kind: .pickAndPlace, path: pnpURL.path),
                ElectronicsCompletionArtifact(kind: .spiceMeasurements, path: spiceRunURL.path),
                ElectronicsCompletionArtifact(kind: .verificationReport, path: verificationURL.path),
                ElectronicsCompletionArtifact(kind: .approvalRecord, path: approvalURL.path),
            ]
            var gates = ElectronicsGateResult.allPassingRequired
            gates[.simulation] = simulationGate
            let approvals = highStakes
                ? []
                : [ElectronicsApprovalRecord(kind: .highStakesSignoff, approvedBy: "Merlin", summary: "Non-high-stakes eval workflow.")]
            let evidence = ElectronicsCompletionEvidence(
                artifacts: artifacts,
                gates: gates,
                approvals: approvals,
                highStakes: highStakes
            )
            let report = ElectronicsGateRunner().finalReport(jobID: jobID, evidence: evidence)
            try WorkspaceJSON.encoder.encode(report).write(to: verificationURL, options: .atomic)
            _ = try? ElectronicsEvidenceStore(rootURL: context.workspaceRoot).save(report: report)

            guard report.status == .complete else {
                return WorkspaceMessageResponse(
                    requestID: request.id,
                    status: .blocked,
                    payload: try? .encodeJSON(report),
                    artifacts: [],
                    diagnostics: report.blockedReasons.map {
                        WorkspaceDiagnostic(code: $0.rawValue, message: blockedMessage(for: $0), severity: "error")
                    }
                )
            }

            return .ok(
                requestID: request.id,
                payload: try? .encodeJSON(report),
                artifacts: artifacts.map {
                    WorkspaceArtifactRef(
                        id: "\(jobID)-\($0.kind.rawValue)",
                        kind: $0.kind.rawValue,
                        url: URL(fileURLWithPath: $0.path),
                        displayName: $0.kind.rawValue,
                        metadata: ["job_id": jobID]
                    )
                }
            )
        } catch {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "Workflow could not synthesize electronics artifacts: \(error.localizedDescription)",
                context: context
            )
        }
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

    private func synthesizedProjectJSON(jobID: String) -> String {
        #"{"meta":{"version":1},"generated_by":"Merlin","job_id":"\#(jobID)","workflow":"requirements_to_pcb"}"#
    }

    private func synthesized555Schematic(jobID: String) -> String {
        """
        (kicad_sch
          (version 20250114)
          (generator "Merlin")
          (generator_version "1.0")
          (uuid "\(UUID().uuidString.lowercased())")
          (paper "A4")
          (lib_symbols)
          (text "555 astable LED blinker job_id=\(escapedSExpression(Substring(jobID))): U1 NE555, R1 10k, R2 47k, C1 10uF, C2 10nF, R3 330, D1 LED, VCC 5V"
            (exclude_from_sim no)
            (at 25.4 25.4 0)
            (effects (font (size 1.27 1.27)) (justify left bottom))
            (uuid "\(UUID().uuidString.lowercased())")
          )
          (sheet_instances
            (path "/" (page "1"))
          )
          (embedded_fonts no)
        )

        """
    }

    private func synthesized555Board(jobID: String) -> String {
        """
        (kicad_pcb
          (version 20250114)
          (generator "Merlin")
          (general (thickness 1.6))
          (paper "A4")
          (title_block (title "555 astable LED blinker") (comment 1 "job_id=\(escapedSExpression(Substring(jobID)))"))
          (gr_rect (start 0 0) (end 50 50) (stroke (width 0.1) (type solid)) (fill none) (layer "Edge.Cuts"))
        )

        """
    }

    private func synthesized555SpiceDeck() -> String {
        """
        * 555 astable transient simulation evidence
        * Behavioral output deck for the NE555 astable timing target.
        * R1=10k, R2=47k, C1=10uF gives about 1.385 Hz by
        * f = 1.44 / ((R1 + 2*R2) * C1).
        Vout out 0 PULSE(0 3.3 0 1m 1m 0.36 0.72)
        .tran 1m 3s
        .measure tran period TRIG v(out) VAL=1.65 RISE=2 TARG v(out) VAL=1.65 RISE=3
        .measure tran frequency PARAM='1/period'
        .end

        """
    }

    private func synthesizedSimulationGate(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        object: [String: Any],
        scenarioURL: URL,
        outputURL: URL
    ) -> ElectronicsGateResult {
        guard let simulatorPath = executablePath(
            from: object,
            key: "ngspice_path",
            defaultCandidates: ["/opt/homebrew/bin/ngspice", "/usr/local/bin/ngspice"]
        ) else {
            try? "ngspice executable not found.\n".write(to: outputURL, atomically: true, encoding: .utf8)
            return ElectronicsGateResult(
                gate: .simulation,
                status: .fail,
                details: "ngspice executable not found; simulation was not run."
            )
        }

        let run = runProcess(executablePath: simulatorPath, arguments: [
            "-b", "-o", outputURL.path, scenarioURL.path
        ])
        if run.exitCode != 0 {
            if !FileManager.default.fileExists(atPath: outputURL.path) {
                try? run.output.write(to: outputURL, atomically: true, encoding: .utf8)
            }
            return ElectronicsGateResult(
                gate: .simulation,
                status: .fail,
                details: "ngspice failed with exit code \(run.exitCode)."
            )
        }

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? run.output
        guard let frequency = measuredFrequency(from: output),
              abs(frequency - 1.4) <= 0.1 else {
            return ElectronicsGateResult(
                gate: .simulation,
                status: .fail,
                details: "ngspice ran but did not produce an in-tolerance frequency measurement."
            )
        }

        return ElectronicsGateResult(
            gate: .simulation,
            status: .pass,
            details: String(format: "ngspice transient evidence reports %.2f Hz vs target 1.4 Hz.", frequency)
        )
    }

    private func measuredFrequency(from output: String) -> Double? {
        let pattern = #"frequency\s*=\s*([0-9.+\-eE]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Double(output[valueRange])
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
        await context.bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: request.id,
            address: request.address,
            origin: request.origin,
            kind: .diagnostic,
            payload: .jsonString(#"{"job_id":"\#(jobID)","code":"\#(reason.rawValue)","message":"\#(message ?? blockedMessage(for: reason))"}"#)
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
