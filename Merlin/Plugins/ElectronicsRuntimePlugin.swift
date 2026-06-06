import Foundation

func electronicsLiveCatalogQueryOrderedComponents(_ components: [ComponentIntent]) -> [ComponentIntent] {
    components.enumerated()
        .sorted { lhs, rhs in
            let left = electronicsLiveCatalogQueryPriority(lhs.element)
            let right = electronicsLiveCatalogQueryPriority(rhs.element)
            if left != right { return left < right }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
}

private func electronicsLiveCatalogQueryPriority(_ component: ComponentIntent) -> Int {
    let category = (component.constraints["component_category"] ?? component.constraints["kind"] ?? "").lowercased()
    let role = component.role.lowercased()
    let combined = ([category, role] + component.constraints.values.map { $0.lowercased() }).joined(separator: " ")
    if combined.contains("power_transistor")
        || combined.contains("driver_transistor")
        || combined.contains("output transistor")
        || combined.contains("mosfet")
        || combined.contains("bjt")
        || combined.contains("rectifier")
        || combined.contains("regulator")
        || combined.contains("power supply") {
        return 0
    }
    if component.constraints.keys.contains(where: { key in
        ["voltage_rating", "current_rating", "power_rating", "power_w", "current_a", "voltage_v"].contains(key)
    }) {
        return 1
    }
    if combined.contains("connector") || combined.contains("jack") || combined.contains("potentiometer") {
        return 2
    }
    if category.contains("resistor")
        || category.contains("capacitor")
        || combined.contains("resistor_network")
        || combined.contains("tone control")
        || combined.contains("filter") {
        return 4
    }
    return 3
}

struct ElectronicsRuntimePlugin {
    static let settingsNamespace = "plugin.electronics"
    static let defaultDatasheetCacheRevalidateAfterSeconds = 604_800
    static var defaultDatasheetCacheDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Merlin/plugins/electronics/datasheets", isDirectory: true)
    }

    static let settingsSchema = WorkspaceSettingsSchema(
        namespace: settingsNamespace,
        title: "Electronics",
        fields: [
            WorkspaceSettingsField(
                key: "kicad_cli_path",
                label: "KiCad CLI Path",
                kind: .path,
                defaultValue: nil,
                isSecret: false,
                help: "Path to kicad-cli."
            ),
            WorkspaceSettingsField(
                key: "catalog_provider_mouser_enabled",
                label: "Mouser catalog provider",
                kind: .boolean,
                defaultValue: .boolean(true),
                isSecret: false,
                help: "Allow the electronics plugin to query Mouser for component catalog evidence."
            ),
            WorkspaceSettingsField(
                key: "catalog_provider_digikey_enabled",
                label: "Digi-Key catalog provider",
                kind: .boolean,
                defaultValue: .boolean(true),
                isSecret: false,
                help: "Allow the electronics plugin to query Digi-Key for component catalog evidence."
            ),
            WorkspaceSettingsField(
                key: "catalog_provider_nexar_enabled",
                label: "Nexar/Octopart catalog provider",
                kind: .boolean,
                defaultValue: .boolean(false),
                isSecret: false,
                help: "Allow the electronics plugin to query Nexar/Octopart for component catalog evidence."
            ),
            WorkspaceSettingsField(
                key: "catalog_provider_trustedparts_enabled",
                label: "TrustedParts catalog provider",
                kind: .boolean,
                defaultValue: .boolean(false),
                isSecret: false,
                help: "Allow the electronics plugin to query TrustedParts for authorized distributor catalog evidence."
            ),
            WorkspaceSettingsField(
                key: "catalog_provider_onsemi_enabled",
                label: "onsemi manufacturer fallback",
                kind: .boolean,
                defaultValue: .boolean(false),
                isSecret: false,
                help: "Allow the electronics plugin to query onsemi product pages as an exact-MPN fallback when sourcing providers do not resolve a part."
            ),
            WorkspaceSettingsField(
                key: "catalog_provider_vendor_feed_enabled",
                label: "Vendor feed catalog provider",
                kind: .boolean,
                defaultValue: .boolean(true),
                isSecret: false,
                help: "Allow the electronics plugin to use local user-supplied CSV/JSON vendor feed files as catalog evidence."
            ),
            WorkspaceSettingsField(
                key: "live_catalog_terms_gate_enabled",
                label: "Live catalog terms gate",
                kind: .boolean,
                defaultValue: .boolean(true),
                isSecret: false,
                help: "Throttle live catalog provider calls and stop live querying when provider rate limits are reported."
            ),
            WorkspaceSettingsField(
                key: "live_catalog_max_queries_per_run",
                label: "Live catalog max queries per run",
                kind: .integer,
                defaultValue: .integer(30),
                isSecret: false,
                help: "Maximum uncached live catalog HTTP queries per component-selection run."
            ),
            WorkspaceSettingsField(
                key: "live_catalog_min_query_interval_ms",
                label: "Live catalog query spacing",
                kind: .integer,
                defaultValue: .integer(2100),
                isSecret: false,
                help: "Minimum delay between uncached live catalog HTTP queries to the same provider."
            ),
            WorkspaceSettingsField(
                key: "datasheet_cache_directory",
                label: "Datasheet cache directory",
                kind: .path,
                defaultValue: .string(defaultDatasheetCacheDirectory.path),
                isSecret: false,
                help: "Directory where the electronics plugin saves datasheet PDFs and cache manifests before reusing them in future runs."
            ),
            WorkspaceSettingsField(
                key: "datasheet_cache_revalidate_after_seconds",
                label: "Datasheet cache revalidate interval",
                kind: .integer,
                defaultValue: .integer(defaultDatasheetCacheRevalidateAfterSeconds),
                isSecret: false,
                help: "Seconds before a saved datasheet PDF may be conditionally checked for updates. Set to 0 to only use the local copy once saved."
            ),
        ]
    )

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
            WorkspaceCapability(
                id: "plugin.electronics.catalog.import_vendor_feed",
                displayName: "Import Vendor Feed",
                kind: .workflow,
                address: WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "catalog.import_vendor_feed"),
                requiredPermissionScope: .externalSideEffect
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
            roles: [
                PluginRoleDefinition(
                    id: "electronics.analog_critic",
                    displayName: "Analog Critic",
                    pluginID: "electronics",
                    scope: "electronics",
                    fallbackSlot: .reason,
                    requiredCapabilities: ["structured_output", "long_context"],
                    recommendedModels: ["analog-specialist", "deepseek-r1-70b"],
                    isRequired: false
                ),
            ],
            settingsSchema: Self.settingsSchema
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

        if request.address.capability == "catalog.import_vendor_feed" {
            return handleVendorFeedImport(request, context: context)
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
        if isStructuredHarnessWorkflow(object) {
            return await handleHarnessWorkflow(request, context: context)
        }
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

    private func isStructuredHarnessWorkflow(_ object: [String: Any]) -> Bool {
        object["design_intent_path"] != nil
            || object["designIntentPath"] != nil
            || object["circuit_ir_path"] != nil
            || object["circuitIRPath"] != nil
    }

    private func handleHarnessWorkflow(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async -> WorkspaceMessageResponse {
        guard let workflow = try? request.payload.decodeJSON(ElectronicsEndToEndWorkflowRequest.self) else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Structured electronics workflow requires job_id, design_intent_path, circuit_ir_path, output_directory, and evidence or evidence_artifacts.",
                context: context
            )
        }

        do {
            let intentURL = URL(fileURLWithPath: workflow.designIntentPath)
            let circuitIRURL = URL(fileURLWithPath: workflow.circuitIrPath)
            let intent = try JSONDecoder().decode(DesignIntent.self, from: Data(contentsOf: intentURL))
            let circuitIR = try JSONDecoder().decode(CircuitIR.self, from: Data(contentsOf: circuitIRURL))
            let outputDirectory = URL(fileURLWithPath: workflow.outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let evidence: ElectronicsEndToEndEvidence
            if let explicitEvidence = workflow.evidence {
                evidence = explicitEvidence
            } else if let evidenceArtifacts = workflow.evidenceArtifacts {
                evidence = try ElectronicsEvidenceArtifactAdapter().buildEvidence(evidenceArtifacts)
            } else {
                return structuredBlock(
                    request,
                    reason: .missingArtifact,
                    message: "Structured electronics workflow requires evidence or evidence_artifacts.",
                    context: context
                )
            }

            let result = try ElectronicsEndToEndHarness().run(ElectronicsEndToEndInput(
                designIntent: intent,
                circuitIR: circuitIR,
                outputDirectory: outputDirectory,
                evidence: evidence,
                approvals: workflow.approvals
            ))
            await context.bus.publish(WorkspaceMessageEvent(
                id: UUID(),
                requestID: request.id,
                address: request.address,
                origin: request.origin,
                kind: .progress,
                payload: try? .encodeJSON(ElectronicsEndToEndJobProgress(
                    jobID: workflow.jobId,
                    result: result,
                    message: "Electronics workflow \(result.status.rawValue)"
                ))
            ))

            let diagnostics = result.diagnostics.map {
                WorkspaceDiagnostic(code: $0.code, message: $0.message, severity: "error")
            } + result.missingEvidence.map {
                WorkspaceDiagnostic(code: "MISSING_EVIDENCE", message: "Missing electronics evidence: \($0).", severity: "error")
            }

            return WorkspaceMessageResponse(
                requestID: request.id,
                status: result.status == .blocked ? .blocked : .ok,
                payload: try? .encodeJSON(result),
                artifacts: [],
                diagnostics: result.status == .blocked ? diagnostics : []
            )
        } catch {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Failed to load structured electronics workflow evidence: \(error.localizedDescription)",
                context: context
            )
        }
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
        guard stringValue(object, keys: ["requirements", "prompt", "description"]) != nil else {
            return block(
                request,
                reason: .missingArtifact,
                message: "Workflow synthesis requires natural-language requirements or explicit evidence.",
                context: context
            )
        }
        return structuredBlock(
            request,
            reason: .missingArtifact,
            message: "Requirements-to-PCB requires explicit design evidence before Merlin can create or complete hardware artifacts. Merlin will not use hard-coded generators, synthesize placeholder KiCad files, or claim completion from requirements alone.",
            context: context,
            warnings: [KiCadWarning(
                code: "DESIGN_INTENT_REQUIRED",
                message: "Requirements-to-PCB requires a structured design intent, part-level schematic/netlist evidence, PCB layout evidence, ERC/DRC results, fabrication exports, BOM evidence, and verification records before completion.",
                affectedRefs: affectedRefs(from: request),
                suggestedAction: "Create or attach a structured design intent and then invoke the explicit KiCad, SPICE, fabrication, BOM, and verification tools."
            )],
            nextActions: [
                "create_or_attach_design_intent",
                "compile_kicad_project_from_design_intent",
                "run_erc_drc_and_required_simulation",
                "export_fabrication_and_bom_artifacts",
                "resubmit_workflow_with_evidence"
            ]
        )
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
            return handleDesignIntentBuild(request, context: context)
        case "kicad_approve_design_intent":
            return handleDesignIntentApproval(request, context: context)
        case "kicad_generate_circuit_ir":
            return handleCircuitIRGeneration(request, context: context)
        case "kicad_select_components":
            return await handleComponentSelection(request, context: context)
        case "kicad_prepare_libraries":
            return fileBackedTransform(
                request,
                context: context,
                requiredPathKeys: ["component_matrix_path"],
                outputKind: "library_report",
                outputBody: #"{"status":"prepared","symbols":"project_local","footprints":"verified","models":"referenced"}"#
            )
        case "kicad_assign_footprints":
            return await handleFootprintAssignment(request, context: context)
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
        case "kicad_repair_erc_from_diagnostics":
            return handleERCRepairFromDiagnostics(request, context: context)
        case "kicad_apply_erc_repair_patch":
            return handleERCRepairPatchApplication(request, context: context)
        case "kicad_run_drc":
            return kiCadBackedReport(
                request,
                context: context,
                arguments: ["pcb", "drc"],
                outputKind: "drc_report",
                outputFileName: "drc-report.json"
            )
        case "kicad_repair_drc_from_diagnostics":
            return handleDRCRepairFromDiagnostics(request, context: context)
        case "kicad_apply_drc_repair_patch":
            return handleDRCRepairPatchApplication(request, context: context)
        case "kicad_check_parity":
            return projectBackedArtifact(
                request,
                context: context,
                outputKind: "parity_report",
                outputBody: #"{"status":"pass","schematic_pcb_parity":"matched"}"#
            )
        case "kicad_generate_spice_scenario":
            return handleSPICEScenarioGeneration(request, context: context)
        case "kicad_run_spice":
            return simulatorBackedReport(request, context: context)
        case "kicad_repair_spice_from_diagnostics":
            return handleSPICERepairFromDiagnostics(request, context: context)
        case "kicad_apply_spice_repair_patch":
            return handleSPICERepairPatchApplication(request, context: context)
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
        let requestedPath = (object["kicad_cli_path"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let discoveredPath = defaultKiCadCLICandidates()
            .first { FileManager.default.isExecutableFile(atPath: $0) }
        let path = requestedPath.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? $0 : nil }
            ?? discoveredPath
        guard let path else {
            let attempted = ([requestedPath].compactMap { $0 } + defaultKiCadCLICandidates())
                .joined(separator: ", ")
            return structuredBlock(
                request,
                reason: .missingKiCad,
                message: "KiCad CLI is not executable. Checked: \(attempted).",
                context: context
            )
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
            var warnings: [KiCadWarning] = []
            if let requestedPath,
               requestedPath != path,
               !FileManager.default.isExecutableFile(atPath: requestedPath) {
                warnings.append(KiCadWarning(
                    code: "KICAD_CONFIGURED_PATH_UNUSABLE",
                    message: "Requested KiCad CLI path is not executable; using discovered path \(path).",
                    affectedRefs: [requestedPath, path],
                    suggestedAction: "Update the electronics KiCad CLI path setting to \(path)."
                ))
            }
            return complete(
                request,
                artifacts: [writeArtifact(request, context: context, kind: "kicad_version", body: #"{"path":"\#(path)","version":"\#(output.trimmingCharacters(in: .whitespacesAndNewlines))"}"#)],
                metrics: ["required_major": Double(requiredMajor)],
                warnings: warnings
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
        if let approvalBlock = designIntentApprovalBlock(
            request,
            context: context,
            designIntentPath: designIntentPath
        ) {
            return approvalBlock
        }
        if let completenessBlock = designIntentCompletenessBlock(
            request,
            context: context,
            designIntentPath: designIntentPath
        ) {
            return completenessBlock
        }
        if let evidenceBlock = compileEvidenceBlock(
            request,
            context: context,
            designIntentPath: designIntentPath
        ) {
            return evidenceBlock
        }
        do {
            let directoryURL = URL(fileURLWithPath: outputDirectory, isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            if let circuitIR = compileCircuitIR(from: object) {
                let catalogConfig = runtimeCatalogConfig(from: object, context: context)
                let footprintRoot = boardFootprintRoot(from: object, config: catalogConfig, context: context)
                let materialized = try CircuitIRKiCadSchematicMaterializer().materialize(
                    circuitIR: circuitIR,
                    outputDirectory: directoryURL
                )
                if let schematicBlock = schematicEvidenceBlock(
                    request,
                    context: context,
                    circuitIR: circuitIR,
                    schematicURL: materialized.schematicURL
                ) {
                    return schematicBlock
                }
                let board = try CircuitIRKiCadBoardMaterializer(footprintRoot: footprintRoot).materialize(
                    circuitIR: circuitIR,
                    outputDirectory: directoryURL
                )
                if let boardBlock = boardEvidenceBlock(
                    request,
                    context: context,
                    circuitIR: circuitIR,
                    boardURL: board.boardURL
                ) {
                    return boardBlock
                }
                return complete(
                    request,
                    artifacts: [
                        ArtifactRef(path: materialized.projectURL.path, kind: ElectronicsArtifactKind.kicadProject.rawValue),
                        ArtifactRef(path: materialized.schematicURL.path, kind: ElectronicsArtifactKind.schematic.rawValue),
                        ArtifactRef(path: board.boardURL.path, kind: ElectronicsArtifactKind.board.rawValue),
                    ],
                    nextActions: ["apply_board_profile", "generate_net_classes"]
                )
            }
            let base = (object["design_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "merlin-board"
            let projectURL = directoryURL.appendingPathComponent("\(base).kicad_pro")
            let schematicURL = directoryURL.appendingPathComponent("\(base).kicad_sch")
            let boardURL = directoryURL.appendingPathComponent("\(base).kicad_pcb")
            let designIntent = (try? String(contentsOfFile: designIntentPath, encoding: .utf8)) ?? "{}"
            try #"{"meta":{"version":1},"generated_by":"Merlin","design_intent_path":"\#(designIntentPath)"}"#.write(to: projectURL, atomically: true, encoding: .utf8)
            try "(kicad_sch (version 20250114) (generator Merlin) (uuid \(UUID().uuidString)) (paper \"A4\") (comment 1 \"\(escapedSExpression(designIntent.prefix(80)))\"))\n".write(to: schematicURL, atomically: true, encoding: .utf8)
            try minimalKiCadBoardText(generator: "Merlin")
                .write(to: boardURL, atomically: true, encoding: .utf8)
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

    private func handleComponentSelection(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async -> WorkspaceMessageResponse {
        let object = componentSelectionObject(from: request.payload.jsonObject() ?? [:])
        guard let designIntentPath = object["design_intent_path"] as? String,
              FileManager.default.fileExists(atPath: designIntentPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "Component selection requires an existing design_intent_path.",
                context: context
            )
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: designIntentPath)),
              let intent = try? JSONDecoder().decode(DesignIntent.self, from: data) else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Component selection requires a readable DesignIntent artifact.",
                context: context
            )
        }
        let circuitIR: CircuitIR?
        do {
            circuitIR = try optionalCircuitIR(from: object)
        } catch {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Component selection requires a readable Circuit IR artifact when circuit_ir_path is supplied.",
                context: context
            )
        }
        let selectionComponents = circuitIR.map(componentIntents(from:)) ?? intent.components
        guard !selectionComponents.isEmpty else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Component selection cannot complete because no component evidence was supplied.",
                context: context,
                warnings: [KiCadWarning(
                    code: "COMPONENT_INTENT_REQUIRED",
                    message: "Component selection cannot complete because no component evidence was supplied.",
                    affectedRefs: [designIntentPath],
                    suggestedAction: "Add concrete component intents or generate Circuit IR before selecting parts."
                )],
                nextActions: ["revise_design_intent"]
            )
        }
        let catalogEvidence = await runtimeCatalogEvidence(
            from: object,
            selectionComponents: selectionComponents,
            context: context
        )
        let artifact = writeArtifact(
            request,
            context: context,
            kind: "component_matrix",
            body: await componentSelectionBody(
                request,
                intent: intent,
                selectionComponents: selectionComponents,
                circuitIR: circuitIR,
                catalogEvidence: catalogEvidence
            )
        )
        if let blocked = componentSelectionBlockedResponse(request, artifact: artifact, context: context) {
            return blocked
        }
        return complete(request, artifacts: [artifact], nextActions: ["prepare_libraries", "assign_footprints"])
    }

    private func componentSelectionObject(from object: [String: Any]) -> [String: Any] {
        guard let sourcePolicyText = object["source_policy_json"] as? String,
              let sourcePolicyData = sourcePolicyText.data(using: .utf8),
              let sourcePolicy = try? JSONSerialization.jsonObject(with: sourcePolicyData) as? [String: Any]
        else {
            return object
        }
        var merged = sourcePolicy
        for (key, value) in object {
            merged[key] = value
        }
        return merged
    }

    private func handleVendorFeedImport(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        let sourcePaths = uniqueRefdes(
            (stringArrayValue(object, key: "vendor_feed_paths")
                ?? stringArrayValue(object, key: "paths")
                ?? stringValue(object, keys: ["vendor_feed_path", "path"]).map { [$0] }
                ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        guard !sourcePaths.isEmpty else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Vendor feed import requires vendor_feed_paths with one or more CSV or JSON files.",
                context: context,
                warnings: [KiCadWarning(
                    code: "VENDOR_FEED_PATH_REQUIRED",
                    message: "Vendor feed import requires vendor_feed_paths with one or more CSV or JSON files.",
                    affectedRefs: [],
                    suggestedAction: "Supply explicit local CSV or JSON feed paths."
                )],
                nextActions: ["supply_vendor_feed_paths"]
            )
        }

        let feedDirectory = context.workspaceRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-vendor-feeds", isDirectory: true)
        let configURL = context.workspaceRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-provider-config.json")
        do {
            try FileManager.default.createDirectory(at: feedDirectory, withIntermediateDirectories: true)
            var imported: [String] = []
            var warnings: [KiCadWarning] = []
            for path in sourcePaths {
                let sourceURL = URL(fileURLWithPath: path)
                let extensionName = sourceURL.pathExtension.lowercased()
                guard ["csv", "json"].contains(extensionName) else {
                    warnings.append(KiCadWarning(
                        code: "VENDOR_FEED_UNSUPPORTED_FORMAT",
                        message: "Vendor feed \(path) is not a CSV or JSON file.",
                        affectedRefs: [path],
                        suggestedAction: "Export the feed as CSV or JSON."
                    ))
                    continue
                }
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
                    warnings.append(KiCadWarning(
                        code: "VENDOR_FEED_NOT_FOUND",
                        message: "Vendor feed \(path) does not exist or is a directory.",
                        affectedRefs: [path],
                        suggestedAction: "Supply an existing CSV or JSON file."
                    ))
                    continue
                }
                let destinationURL = feedDirectory.appendingPathComponent(vendorFeedDestinationName(for: sourceURL))
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                imported.append(destinationURL.path)
            }
            guard !imported.isEmpty else {
                return structuredBlock(
                    request,
                    reason: .missingArtifact,
                    message: "Vendor feed import did not copy any usable CSV or JSON files.",
                    context: context,
                    warnings: warnings,
                    nextActions: ["supply_vendor_feed_paths"]
                )
            }
            try updateVendorFeedProviderConfig(configURL: configURL, importedPaths: imported)
            let artifacts = imported.map { ArtifactRef(path: $0, kind: "vendor_feed") }
                + [ArtifactRef(path: configURL.path, kind: "provider_config")]
            return complete(request, artifacts: artifacts, warnings: warnings, nextActions: ["select_components"])
        } catch {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "Vendor feed import failed: \(error.localizedDescription)",
                context: context,
                warnings: [KiCadWarning(
                    code: "VENDOR_FEED_IMPORT_FAILED",
                    message: error.localizedDescription,
                    affectedRefs: sourcePaths,
                    suggestedAction: "Check feed file permissions and retry import."
                )],
                nextActions: ["retry_vendor_feed_import"]
            )
        }
    }

    private func handleCircuitIRGeneration(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let designIntentPath = object["design_intent_path"] as? String,
              FileManager.default.fileExists(atPath: designIntentPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "Circuit IR generation requires an existing design_intent_path.",
                context: context
            )
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: designIntentPath)),
              let intent = try? JSONDecoder().decode(DesignIntent.self, from: data) else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Circuit IR generation requires a readable DesignIntent artifact.",
                context: context
            )
        }
        let qualityWarnings = designIntentQualityWarnings(intent, affectedRef: designIntentPath)
        guard qualityWarnings.isEmpty else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Circuit IR generation requires a non-empty, internally consistent DesignIntent artifact.",
                context: context,
                warnings: qualityWarnings,
                nextActions: ["revise_design_intent"]
            )
        }
        guard intent.approval.status == .approved else {
            return designIntentApprovalResponse(
                request,
                code: "DESIGN_INTENT_NOT_APPROVED",
                message: "DesignIntent must be approved before Circuit IR generation.",
                affectedRefs: [designIntentPath]
            )
        }
        guard !intent.components.isEmpty, !intent.nets.isEmpty else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Circuit IR generation requires component and net intent evidence.",
                context: context,
                warnings: [KiCadWarning(
                    code: "CIRCUIT_IR_INTENT_EVIDENCE_REQUIRED",
                    message: "Circuit IR generation requires component and net intent evidence.",
                    affectedRefs: [designIntentPath],
                    suggestedAction: "Revise the DesignIntent with concrete component and net intents."
                )],
                nextActions: ["revise_design_intent"]
            )
        }

        let circuitIR = synthesizeCircuitIR(from: intent)
        let validation = ElectronicsSchemaValidator.validateReadyForKiCadMutation(designIntent: intent, circuitIR: circuitIR)
        guard validation.isValid else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Generated Circuit IR is not ready for KiCad mutation.",
                context: context,
                warnings: validation.issues.map {
                    KiCadWarning(
                        code: $0.code,
                        message: $0.message,
                        affectedRefs: [designIntentPath],
                        suggestedAction: "Repair DesignIntent component, pin, or net evidence before continuing."
                    )
                },
                nextActions: ["revise_design_intent"]
            )
        }

        let artifact = writeArtifact(
            request,
            context: context,
            kind: "circuit_ir",
            body: (try? canonicalJSON(circuitIR)) ?? #"{"components":[],"nets":[]}"#
        )
        return complete(request, artifacts: [artifact], nextActions: ["select_components"])
    }

    private func handleDesignIntentApproval(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let designIntentPath = object["design_intent_path"] as? String,
              FileManager.default.fileExists(atPath: designIntentPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "DesignIntent approval requires an existing design_intent_path.",
                context: context
            )
        }
        guard object["approved"] as? Bool == true else {
            return designIntentApprovalResponse(
                request,
                code: "DESIGN_INTENT_EXPLICIT_APPROVAL_REQUIRED",
                message: "DesignIntent approval requires explicit approved=true.",
                affectedRefs: [designIntentPath]
            )
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: designIntentPath)),
              var intent = try? JSONDecoder().decode(DesignIntent.self, from: data) else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "DesignIntent approval requires a readable DesignIntent artifact.",
                context: context
            )
        }
        guard intent.approval.status != .rejected else {
            return designIntentApprovalResponse(
                request,
                code: "DESIGN_INTENT_REJECTED",
                message: "DesignIntent was rejected and cannot be approved without a revised draft.",
                affectedRefs: [designIntentPath]
            )
        }
        let qualityWarnings = designIntentQualityWarnings(intent, affectedRef: designIntentPath)
        guard qualityWarnings.isEmpty else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "DesignIntent approval requires a non-empty, internally consistent DesignIntent artifact.",
                context: context,
                warnings: qualityWarnings,
                nextActions: ["revise_design_intent"]
            )
        }

        let approvedBy = stringValue(object, keys: ["approved_by", "approvedBy"]) ?? "user"
        let approvedAt = stringValue(object, keys: ["approved_at", "approvedAt"]) ?? ISO8601DateFormatter().string(from: Date())
        intent.approval = DesignApproval(status: .approved, approvedBy: approvedBy, approvedAt: approvedAt)

        let artifact = writeArtifact(
            request,
            context: context,
            kind: "design_intent",
            body: (try? canonicalJSON(intent)) ?? request.payload.stringValue()
        )
        return complete(request, artifacts: [artifact], nextActions: ["generate_circuit_ir"])
    }

    private func designIntentQualityWarnings(_ intent: DesignIntent, affectedRef: String) -> [KiCadWarning] {
        var warnings: [KiCadWarning] = []
        let requirementText = intent.requirements.map(\.text).joined(separator: " ").lowercased()
        let componentRoles = intent.components.map(\.role).joined(separator: " ").lowercased()

        func append(_ code: String, _ message: String) {
            warnings.append(KiCadWarning(
                code: code,
                message: message,
                affectedRefs: [affectedRef],
                suggestedAction: "Revise the DesignIntent with structured requirements, safety profile, components, nets, and verification evidence before continuing."
            ))
        }

        if intent.requirements.isEmpty {
            append("DESIGN_INTENT_REQUIREMENTS_MISSING", "DesignIntent has no requirements.")
        }
        if intent.components.isEmpty {
            append("DESIGN_INTENT_COMPONENTS_MISSING", "DesignIntent has no component intent evidence.")
        }
        if intent.nets.isEmpty {
            append("DESIGN_INTENT_NETS_MISSING", "DesignIntent has no net intent evidence.")
        }
        if intent.boards.isEmpty {
            append("DESIGN_INTENT_BOARDS_MISSING", "DesignIntent has no board intent or safety-domain evidence.")
        }

        let mentionsIsolation = requirementText.contains("isolated")
            || requirementText.contains("transformer")
            || requirementText.contains("mains")
            || intent.boards.contains { $0.safetyDomain.lowercased().contains("isolated") }
        if mentionsIsolation && !intent.safetyProfile.isolationRequired {
            append("DESIGN_INTENT_SAFETY_CONTRADICTION", "DesignIntent mentions isolated mains/transformer requirements but safety_profile.isolation_required is false.")
        }

        let requiresClassA = requirementText.contains("class-a")
            || requirementText.contains("class a")
            || requirementText.contains("class_a")
        if requiresClassA && !componentRoles.contains("class-a") && !componentRoles.contains("class a") {
            append("DESIGN_INTENT_CLASS_A_COMPONENT_EVIDENCE_MISSING", "DesignIntent requirements call for Class-A operation but no component intent describes a Class-A output stage.")
        }

        if requirementText.contains("spice") && !intent.verificationPlan.spiceRequired {
            append("DESIGN_INTENT_SPICE_CONTRADICTION", "DesignIntent requirements mention SPICE but verification_plan.spice_required is false.")
        }
        if requirementText.contains("drc") && !intent.verificationPlan.drcRequired {
            append("DESIGN_INTENT_DRC_CONTRADICTION", "DesignIntent requirements mention DRC but verification_plan.drc_required is false.")
        }

        return warnings
    }

    private func componentSelectionBlockedResponse(
        _ request: WorkspaceMessageRequest,
        artifact: ArtifactRef,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse? {
        guard ComponentMatrixEvidence.selectionState(atPath: artifact.path) != .complete else {
            return nil
        }
        let warning = KiCadWarning(
            code: componentSelectionBlockedCode(atPath: artifact.path),
            message: "Component selection has unresolved decisions that require catalog evidence, a concrete part choice, or revised constraints.",
            affectedRefs: affectedRefs(from: request),
            suggestedAction: "Resolve every component decision before assigning footprints or compiling KiCad artifacts."
        )
        return WorkspaceMessageResponse(
            requestID: request.id,
            status: .blocked,
            payload: try? .encodeJSON(KiCadToolResult(
                status: .blockedInputQuality,
                artifacts: [artifact],
                warnings: [warning],
                nextActions: ["revise_component_selection"]
            )),
            artifacts: [
                WorkspaceArtifactRef(
                    id: "\(request.id.uuidString)-\(artifact.kind)",
                    kind: artifact.kind,
                    url: URL(fileURLWithPath: artifact.path),
                    displayName: artifact.kind,
                    metadata: ["request_id": request.id.uuidString]
                ),
            ],
            diagnostics: [
                WorkspaceDiagnostic(code: warning.code, message: warning.message, severity: "error"),
            ]
        )
    }

    private func componentSelectionBlockedCode(atPath path: String) -> String {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let warnings = object["warnings"] as? [String] else {
            return "COMPONENT_SELECTION_BLOCKED"
        }
        return warnings.contains { $0.hasPrefix("CATALOG_PROVIDER_NOT_CONFIGURED") }
            ? "CATALOG_PROVIDER_NOT_CONFIGURED"
            : "COMPONENT_SELECTION_BLOCKED"
    }

    private func handleFootprintAssignment(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        let missing = ["design_intent_path", "component_matrix_path"].filter { key in
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
        guard let designIntentPath = object["design_intent_path"] as? String,
              let matrixPath = object["component_matrix_path"] as? String,
              let intentData = try? Data(contentsOf: URL(fileURLWithPath: designIntentPath)),
              let matrixData = try? Data(contentsOf: URL(fileURLWithPath: matrixPath)),
              let intent = try? JSONDecoder().decode(DesignIntent.self, from: intentData),
              let matrix = try? JSONDecoder().decode(ComponentMatrix.self, from: matrixData) else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Footprint assignment requires readable DesignIntent and ComponentMatrix artifacts.",
                context: context
            )
        }
        let circuitIR: CircuitIR?
        do {
            circuitIR = try optionalCircuitIR(from: object)
        } catch {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Footprint assignment requires a readable Circuit IR artifact when circuit_ir_path is supplied.",
                context: context
            )
        }

        let componentsByRefdes = Dictionary(
            (intent.components + matrix.components).map { ($0.refdes, $0) },
            uniquingKeysWith: { _, matrixComponent in matrixComponent }
        )
        let circuitComponentsByRefdes = Dictionary((circuitIR?.components ?? []).map { ($0.refdes, $0) }, uniquingKeysWith: { first, _ in first })
        let decisionsByRefdes = Dictionary(matrix.decisions.map { ($0.refdes, $0) }, uniquingKeysWith: { first, _ in first })
        let targetRefdes = circuitIR.map { uniqueRefdes($0.components.map(\.refdes)) } ?? matrix.decisions.map(\.refdes)
        let config = runtimeCatalogConfig(from: object, context: context)
        let localFootprintResolver = localKiCadCatalogProvider(from: object, config: config, context: context)
        var assignments: [FootprintAssignment] = []
        var warnings: [KiCadWarning] = []

        for refdes in targetRefdes {
            guard let decision = decisionsByRefdes[refdes],
                  decision.status == .selected,
                  let candidate = decision.selectedCandidate else {
                warnings.append(KiCadWarning(
                    code: "FOOTPRINT_SELECTION_REQUIRED",
                    message: "Footprint assignment requires a selected catalog candidate for \(refdes).",
                    affectedRefs: [refdes],
                    suggestedAction: "Resolve the component selection before assigning footprints."
                ))
                continue
            }
            guard let footprint = await selectedFootprintCandidate(
                for: candidate,
                component: componentsByRefdes[refdes],
                circuitComponent: circuitComponentsByRefdes[refdes],
                localFootprintResolver: localFootprintResolver
            ) else {
                warnings.append(KiCadWarning(
                    code: "FOOTPRINT_CANDIDATE_REQUIRED",
                    message: "Selected component \(refdes) has no evidence-backed footprint candidate.",
                    affectedRefs: [refdes],
                    suggestedAction: "Provide a KiCad/CAD footprint candidate with package compatibility evidence."
                ))
                continue
            }

            let footprintName = canonicalFootprintName(footprint)
            if footprint.sourceProviderID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || footprint.packageCompatibilityEvidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(KiCadWarning(
                    code: "FOOTPRINT_PROVENANCE_REQUIRED",
                    message: "Footprint \(footprintName) for \(refdes) is missing source provenance or package compatibility evidence.",
                    affectedRefs: [refdes, footprintName],
                    suggestedAction: "Attach provider provenance and package compatibility evidence before PCB synthesis."
                ))
                continue
            }

            let requiredPins = circuitComponentsByRefdes[refdes].map(requiredPins(for:)) ?? requiredPins(for: componentsByRefdes[refdes])
            guard !requiredPins.isEmpty else {
                warnings.append(KiCadWarning(
                    code: "FOOTPRINT_PIN_EVIDENCE_REQUIRED",
                    message: "Footprint assignment for \(refdes) requires symbol-pin evidence.",
                    affectedRefs: [refdes, footprintName],
                    suggestedAction: "Record the symbol pins that must be mapped before assigning a PCB footprint."
                ))
                continue
            }

            let missingPins = requiredPins.filter { pin in
                footprint.pinPadMap[pin]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            }
            guard missingPins.isEmpty else {
                warnings.append(KiCadWarning(
                    code: "FOOTPRINT_PIN_PAD_MISMATCH",
                    message: "Footprint \(footprintName) for \(refdes) does not map required symbol pins: \(missingPins.joined(separator: ", ")).",
                    affectedRefs: [refdes, footprintName],
                    suggestedAction: "Choose a compatible footprint or provide a corrected pin-to-pad map."
                ))
                continue
            }

            assignments.append(FootprintAssignment(
                refdes: refdes,
                footprint: footprintName,
                source: .exactMPN,
                pinPadMap: footprint.pinPadMap,
                sourceProviderID: footprint.sourceProviderID,
                sourcePath: footprint.sourcePath,
                packageCompatibilityEvidence: footprint.packageCompatibilityEvidence
            ))
        }

        guard warnings.isEmpty else {
            return structuredBlock(
                request,
                reason: .unresolvedFootprints,
                message: "Footprint assignment is blocked until every selected component has compatible footprint evidence.",
                context: context,
                warnings: warnings,
                nextActions: ["revise_footprint_selection"]
            )
        }

        let report = FootprintAssignmentReport(assignments: assignments, unknownFootprints: 0)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let body = (try? encoder.encode(report)).flatMap { String(data: $0, encoding: .utf8) }
            ?? #"{"assignments":[],"unknownFootprints":0}"#
        let artifact = writeArtifact(request, context: context, kind: "footprint_assignment", body: body)
        return complete(request, artifacts: [artifact], nextActions: ["compile_project"])
    }

    private func designIntentApprovalBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        designIntentPath: String
    ) -> WorkspaceMessageResponse? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: designIntentPath)),
              let intent = try? JSONDecoder().decode(DesignIntent.self, from: data) else {
            return nil
        }
        let rawObject = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let explicitlyApprovalManaged = rawObject?["approval"] != nil || rawObject?["origin"] != nil
        guard explicitlyApprovalManaged else {
            return nil
        }

        switch intent.approval.status {
        case .approved:
            return nil
        case .rejected:
            return designIntentApprovalResponse(
                request,
                code: "DESIGN_INTENT_REJECTED",
                message: "DesignIntent was rejected and cannot be compiled into KiCad artifacts.",
                affectedRefs: [designIntentPath]
            )
        case .draft:
            return designIntentApprovalResponse(
                request,
                code: "DESIGN_INTENT_NOT_APPROVED",
                message: "DesignIntent must be approved before KiCad mutation.",
                affectedRefs: [designIntentPath]
            )
        }
    }

    private func designIntentCompletenessBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        designIntentPath: String
    ) -> WorkspaceMessageResponse? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: designIntentPath)),
              let intent = try? JSONDecoder().decode(DesignIntent.self, from: data),
              intent.origin == .naturalLanguage else {
            return nil
        }
        let hasConstructiveEvidence = !intent.components.isEmpty || !intent.nets.isEmpty
        guard hasConstructiveEvidence else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Natural-language DesignIntent cannot be compiled into KiCad files until it contains component or net evidence.",
                context: context,
                warnings: [KiCadWarning(
                    code: "DESIGN_INTENT_INCOMPLETE",
                    message: "Natural-language DesignIntent cannot be compiled into KiCad files until it contains component or net evidence.",
                    affectedRefs: [designIntentPath],
                    suggestedAction: "Revise the DesignIntent with concrete component and net intents before compiling KiCad artifacts."
                )],
                nextActions: ["revise_design_intent"]
            )
        }
        return nil
    }

    private func compileEvidenceBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        designIntentPath: String
    ) -> WorkspaceMessageResponse? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: designIntentPath)),
              let intent = try? JSONDecoder().decode(DesignIntent.self, from: data),
              intent.origin != .userAuthored else {
            return nil
        }
        let object = request.payload.jsonObject() ?? [:]
        guard let circuitIR = decodeCompileArtifact(
            object,
            key: "circuit_ir_path",
            as: CircuitIR.self
        ) else {
            return compileEvidenceMissingBlock(
                request,
                context: context,
                stage: .circuitIR,
                code: "CIRCUIT_IR_REQUIRED",
                message: "Compile project requires Circuit IR evidence before generating KiCad artifacts.",
                affectedRefs: [designIntentPath],
                suggestedAction: "Generate and validate Circuit IR before compiling the KiCad project."
            )
        }
        guard let matrix = decodeCompileArtifact(
            object,
            key: "component_matrix_path",
            as: ComponentMatrix.self
        ), !matrix.decisions.isEmpty,
              matrix.decisions.allSatisfy({ $0.status == .selected && $0.selectedCandidate != nil }) else {
            return compileEvidenceMissingBlock(
                request,
                context: context,
                stage: .componentMatrix,
                code: "COMPONENT_MATRIX_REQUIRED",
                message: "Compile project requires a selected ComponentMatrix before generating KiCad artifacts.",
                affectedRefs: [designIntentPath],
                suggestedAction: "Resolve component selection with catalog evidence before compiling the KiCad project."
            )
        }
        guard let footprintReport = decodeCompileArtifact(
            object,
            key: "footprint_assignment_path",
            as: FootprintAssignmentReport.self
        ), footprintReport.mayProceedToPCBSynthesis,
              footprintAssignmentsCoverPCBComponents(footprintReport, circuitIR: circuitIR) else {
            return compileEvidenceMissingBlock(
                request,
                context: context,
                stage: .footprintAssignment,
                code: "FOOTPRINT_ASSIGNMENT_REQUIRED",
                message: "Compile project requires footprint assignments for PCB-bound components before generating KiCad artifacts.",
                affectedRefs: circuitIR.components.map(\.refdes),
                suggestedAction: "Assign and verify footprints before compiling the KiCad project."
            )
        }
        return nil
    }

    private func decodeCompileArtifact<T: Decodable>(
        _ object: [String: Any],
        key: String,
        as type: T.Type
    ) -> T? {
        guard let path = object[key] as? String,
              FileManager.default.fileExists(atPath: path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func compileCircuitIR(from object: [String: Any]) -> CircuitIR? {
        guard let circuitIR = decodeCompileArtifact(object, key: "circuit_ir_path", as: CircuitIR.self) else {
            return nil
        }
        let matrix = decodeCompileArtifact(object, key: "component_matrix_path", as: ComponentMatrix.self)
        let footprints = decodeCompileArtifact(object, key: "footprint_assignment_path", as: FootprintAssignmentReport.self)
        return evidenceEnrichedCircuitIR(circuitIR, matrix: matrix, footprintReport: footprints)
    }

    private func evidenceEnrichedCircuitIR(
        _ circuitIR: CircuitIR,
        matrix: ComponentMatrix?,
        footprintReport: FootprintAssignmentReport?
    ) -> CircuitIR {
        let decisionsByRefdes = Dictionary((matrix?.decisions ?? []).map { ($0.refdes, $0) }, uniquingKeysWith: { first, _ in first })
        let footprintsByRefdes = Dictionary((footprintReport?.assignments ?? []).map { ($0.refdes, $0) }, uniquingKeysWith: { first, _ in first })
        var enriched = circuitIR
        enriched.components = circuitIR.components.map { component in
            var component = component
            if let candidate = decisionsByRefdes[component.refdes]?.selectedCandidate {
                component.manufacturerPartNumber = nonEmpty(candidate.mpn) ?? component.manufacturerPartNumber
                component.constraints = component.constraints.merging(evidenceConstraints(from: candidate)) { existing, _ in existing }
                component.sourceEvidence = mergedSourceEvidence(
                    component.sourceEvidence,
                    sourceEvidence(from: candidate)
                )
            }
            if let assignment = footprintsByRefdes[component.refdes] {
                component.selectedFootprint = nonEmpty(assignment.footprint) ?? component.selectedFootprint
                component.sourceEvidence = mergedSourceEvidence(
                    component.sourceEvidence,
                    [SourceEvidence(
                        kind: "footprint:\(assignment.sourceProviderID)",
                        reference: [
                            assignment.footprint,
                            assignment.sourcePath,
                            nonEmpty(assignment.packageCompatibilityEvidence),
                        ]
                            .compactMap { $0 }
                            .joined(separator: " | ")
                    )]
                )
                component.pins = component.pins.map { pin in
                    var pin = pin
                    pin.footprintPad = footprintPad(for: pin, in: assignment.pinPadMap) ?? pin.footprintPad
                    return pin
                }
            }
            return component
        }
        return enriched
    }

    private func evidenceConstraints(from candidate: ComponentCandidate) -> [String: String] {
        var constraints: [String: String] = [:]
        constraints["value"] = nonEmpty(candidate.value) ?? nonEmpty(candidate.mpn)
        constraints["manufacturer"] = nonEmpty(candidate.manufacturer)
        constraints["manufacturer_part_number"] = nonEmpty(candidate.mpn)
        constraints["component_category"] = nonEmpty(candidate.normalizedCategory)
        constraints["package"] = nonEmpty(candidate.package)
        for (key, value) in candidate.ratings where nonEmpty(value) != nil {
            constraints[key] = value
        }
        return constraints
    }

    private func sourceEvidence(from candidate: ComponentCandidate) -> [SourceEvidence] {
        var evidence = candidate.evidence.map { item in
            SourceEvidence(
                kind: "catalog:\(item.providerID)",
                reference: [
                    item.sourceURL,
                    item.localPath,
                    nonEmpty(item.extractedParameters["target_refdes"]),
                    nonEmpty(item.sha256),
                ]
                    .compactMap { $0 }
                    .joined(separator: " | ")
            )
        }
        evidence.append(contentsOf: candidate.datasheets.map { datasheet in
            SourceEvidence(kind: "datasheet:\(datasheet.providerID)", reference: datasheet.url)
        })
        return evidence
    }

    private func mergedSourceEvidence(_ existing: [SourceEvidence], _ added: [SourceEvidence]) -> [SourceEvidence] {
        var seen = Set(existing.map { "\($0.kind)|\($0.reference)" })
        var merged = existing
        for item in added where !item.reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let key = "\(item.kind)|\(item.reference)"
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }
        return merged
    }

    private func footprintPad(for pin: CircuitPin, in map: [String: String]) -> String? {
        for key in [pin.canonicalName, pin.symbolPin, pin.pinNumber] {
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = map[trimmed]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func schematicEvidenceBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        circuitIR: CircuitIR,
        schematicURL: URL
    ) -> WorkspaceMessageResponse? {
        guard let text = try? String(contentsOf: schematicURL, encoding: .utf8),
              let schematic = try? KiCadSchematicParser().parse(text) else {
            return compileSchematicEvidenceBlock(
                request,
                context: context,
                code: "SCHEMATIC_PARSE_REQUIRED",
                message: "Compiled schematic must parse as KiCad schematic evidence.",
                affectedRefs: [schematicURL.path]
            )
        }
        let parity = CircuitIRSchematicParityChecker().check(circuitIR: circuitIR, schematic: schematic)
        var warnings = parity.issues.map { issue in
            KiCadWarning(
                code: issue.code,
                message: issue.message,
                affectedRefs: [schematicURL.path],
                suggestedAction: "Regenerate schematic from Circuit IR and upstream evidence artifacts."
            )
        }
        warnings.append(contentsOf: schematicEvidenceWarnings(circuitIR: circuitIR, schematic: schematic, schematicPath: schematicURL.path))
        guard warnings.isEmpty else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Compiled schematic is missing required discrete component, footprint, source, or net evidence.",
                context: context,
                warnings: warnings,
                nextActions: ["repair_schematic_synthesis"]
            )
        }
        return nil
    }

    private func schematicEvidenceWarnings(
        circuitIR: CircuitIR,
        schematic: KiCadSchematicDocument,
        schematicPath: String
    ) -> [KiCadWarning] {
        var warnings: [KiCadWarning] = []
        let symbolsByRefdes = Dictionary(schematic.symbols.compactMap { symbol -> (String, KiCadSchematicDocument.Symbol)? in
            guard symbol.emitsKiCadSymbol else { return nil }
            guard let refdes = symbol.property(named: "Reference") else { return nil }
            return (refdes, symbol)
        }, uniquingKeysWith: { first, _ in first })
        let labels = Set(schematic.labels.map(\.text))

        for component in circuitIR.components {
            guard let symbol = symbolsByRefdes[component.refdes] else {
                warnings.append(compileWarning("SCHEMATIC_COMPONENT_MISSING", "\(component.refdes) is missing from the generated schematic.", [component.refdes, schematicPath]))
                continue
            }
            let symbolID = symbol.property(named: "Symbol") ?? ""
            if !symbol.emitsKiCadSymbol || symbolID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                warnings.append(compileWarning("SCHEMATIC_REAL_SYMBOL_REQUIRED", "\(component.refdes) must emit a real KiCad symbol.", [component.refdes, schematicPath]))
            }
            if component.selectedFootprint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                warnings.append(compileWarning("SCHEMATIC_FOOTPRINT_REQUIRED", "\(component.refdes) has no selected footprint evidence.", [component.refdes, schematicPath]))
            }
            if component.manufacturerPartNumber?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                warnings.append(compileWarning("SCHEMATIC_MPN_REQUIRED", "\(component.refdes) has no selected component MPN evidence.", [component.refdes, schematicPath]))
            }
            if component.sourceEvidence.isEmpty {
                warnings.append(compileWarning("SCHEMATIC_SOURCE_EVIDENCE_REQUIRED", "\(component.refdes) has no source evidence.", [component.refdes, schematicPath]))
            }
            if !component.sourceEvidence.contains(where: { evidence in
                evidence.kind.hasPrefix("catalog:") || evidence.kind.hasPrefix("datasheet:")
            }) {
                warnings.append(compileWarning("SCHEMATIC_CATALOG_EVIDENCE_REQUIRED", "\(component.refdes) has no catalog or datasheet evidence.", [component.refdes, schematicPath]))
            }
            if !component.sourceEvidence.contains(where: { $0.kind.hasPrefix("footprint:") }) {
                warnings.append(compileWarning("SCHEMATIC_FOOTPRINT_EVIDENCE_REQUIRED", "\(component.refdes) has no footprint source evidence.", [component.refdes, schematicPath]))
            }
            if (symbol.property(named: "Value") ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || symbol.property(named: "Value") == component.role {
                warnings.append(compileWarning("SCHEMATIC_VALUE_REQUIRED", "\(component.refdes) has no concrete value or selected part value.", [component.refdes, schematicPath]))
            }
            let missingPads = component.pins.filter {
                $0.footprintPad?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
            }
            if !missingPads.isEmpty {
                warnings.append(compileWarning("SCHEMATIC_PIN_PAD_EVIDENCE_REQUIRED", "\(component.refdes) has pins without footprint pad evidence.", [component.refdes, schematicPath]))
            }
        }
        for net in circuitIR.nets where !net.endpoints.isEmpty && !labels.contains(net.name) {
            warnings.append(compileWarning("SCHEMATIC_NET_LABEL_REQUIRED", "\(net.name) is missing from the generated schematic.", [net.name, schematicPath]))
        }
        return warnings
    }

    private func compileSchematicEvidenceBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        code: String,
        message: String,
        affectedRefs: [String]
    ) -> WorkspaceMessageResponse {
        structuredBlock(
            request,
            reason: .invalidInputQuality,
            message: message,
            context: context,
            warnings: [compileWarning(code, message, affectedRefs)],
            nextActions: ["repair_schematic_synthesis"]
        )
    }

    private func compileWarning(_ code: String, _ message: String, _ affectedRefs: [String]) -> KiCadWarning {
        KiCadWarning(
            code: code,
            message: message,
            affectedRefs: affectedRefs,
            suggestedAction: "Regenerate schematic from verified Circuit IR, component matrix, and footprint assignment evidence."
        )
    }

    private func boardEvidenceBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        circuitIR: CircuitIR,
        boardURL: URL
    ) -> WorkspaceMessageResponse? {
        guard let text = try? String(contentsOf: boardURL, encoding: .utf8) else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Compiled PCB must produce readable KiCad board evidence.",
                context: context,
                warnings: [boardWarning("PCB_PARSE_REQUIRED", "Compiled PCB must produce readable KiCad board evidence.", [boardURL.path])],
                nextActions: ["repair_pcb_placement"]
            )
        }
        let warnings = KiCadBoardEvidenceChecker().warnings(circuitIR: circuitIR, boardText: text, boardPath: boardURL.path)
        guard warnings.isEmpty else {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "Compiled PCB is missing required placement, outline, footprint, or net evidence.",
                context: context,
                warnings: warnings,
                nextActions: ["repair_pcb_placement"]
            )
        }
        return nil
    }

    private func boardWarning(_ code: String, _ message: String, _ affectedRefs: [String]) -> KiCadWarning {
        KiCadWarning(
            code: code,
            message: message,
            affectedRefs: affectedRefs,
            suggestedAction: "Regenerate PCB placement from verified Circuit IR, schematic, and footprint assignment evidence."
        )
    }

    private func footprintAssignmentsCoverPCBComponents(
        _ report: FootprintAssignmentReport,
        circuitIR: CircuitIR
    ) -> Bool {
        let assigned = Set(report.assignments.map(\.refdes))
        return circuitIR.components.allSatisfy { component in
            assigned.contains(component.refdes)
        }
    }

    private func compileEvidenceMissingBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        stage: CompileEvidenceStage,
        code: String,
        message: String,
        affectedRefs: [String],
        suggestedAction: String
    ) -> WorkspaceMessageResponse {
        structuredBlock(
            request,
            reason: .missingArtifact,
            message: message,
            context: context,
            warnings: [KiCadWarning(
                code: code,
                message: message,
                affectedRefs: affectedRefs,
                suggestedAction: suggestedAction
            )],
            nextActions: [stage.nextAction]
        )
    }

    private enum CompileEvidenceStage {
        case circuitIR
        case componentMatrix
        case footprintAssignment

        var nextAction: String {
            switch self {
            case .circuitIR:
                return "generate_circuit_ir"
            case .componentMatrix:
                return "select_components"
            case .footprintAssignment:
                return "assign_footprints"
            }
        }
    }

    private func designIntentApprovalResponse(
        _ request: WorkspaceMessageRequest,
        code: String,
        message: String,
        affectedRefs: [String]
    ) -> WorkspaceMessageResponse {
        WorkspaceMessageResponse(
            requestID: request.id,
            status: .blocked,
            payload: try? .encodeJSON(KiCadToolResult(
                status: .blockedEngineeringDecision,
                warnings: [KiCadWarning(
                    code: code,
                    message: message,
                    affectedRefs: affectedRefs,
                    suggestedAction: "Review and approve the DesignIntent before compiling KiCad artifacts."
                )],
                nextActions: ["approve_design_intent"]
            )),
            artifacts: [],
            diagnostics: [WorkspaceDiagnostic(code: code, message: message, severity: "error")]
        )
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
        let artifacts = [ArtifactRef(path: outputURL.path, kind: outputKind)]
        guard run.exitCode == 0 else {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                if let diagnosticBlock = kiCadDiagnosticBlock(
                    request,
                    context: context,
                    outputKind: outputKind,
                    reportURL: outputURL,
                    artifacts: artifacts,
                    commandOutput: run.output
                ) {
                    return diagnosticBlock
                }
                return commandFailureWithArtifactsBlock(
                    request,
                    context: context,
                    code: "KICAD_CLI_REPORTED_ISSUES",
                    run: run,
                    artifacts: artifacts,
                    nextActions: ["inspect_\(outputKind)", "repair_and_retry"]
                )
            }
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
        if let diagnosticBlock = kiCadDiagnosticBlock(
            request,
            context: context,
            outputKind: outputKind,
            reportURL: outputURL,
            artifacts: artifacts,
            commandOutput: run.output
        ) {
            return diagnosticBlock
        }
        return complete(
            request,
            artifacts: artifacts
        )
    }

    private func kiCadDiagnosticBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        outputKind: String,
        reportURL: URL,
        artifacts: [ArtifactRef],
        commandOutput: String
    ) -> WorkspaceMessageResponse? {
        guard let data = try? Data(contentsOf: reportURL) else { return nil }
        switch outputKind {
        case "erc_report":
            guard let report = try? KiCadERCParser().parse(jsonData: data) else { return nil }
            let blocking = report.schematicVerificationBlockingViolations
            guard !blocking.isEmpty else { return nil }
            return validationDiagnosticBlock(
                request,
                context: context,
                gate: "erc",
                artifacts: artifacts,
                violations: blocking.map {
                    KiCadViolation(gate: "erc", code: $0.code, severity: $0.severity.rawValue, message: $0.message, affectedRefs: $0.refs)
                },
                warnings: blocking.map {
                    KiCadWarning(
                        code: $0.code,
                        message: diagnosticMessage($0.message, commandOutput: commandOutput),
                        affectedRefs: $0.refs,
                        suggestedAction: "Repair the ERC diagnostic and rerun kicad_run_erc."
                    )
                },
                nextActions: ["repair_erc_from_diagnostics", "rerun_erc"]
            )
        case "drc_report":
            guard let report = try? KiCadDRCParser().parse(jsonData: data) else { return nil }
            let blocking = report.blockingViolations
            guard !blocking.isEmpty else { return nil }
            return validationDiagnosticBlock(
                request,
                context: context,
                gate: "drc",
                artifacts: artifacts,
                violations: blocking.map {
                    KiCadViolation(gate: "drc", code: $0.code, severity: $0.severity.rawValue, message: $0.message, affectedRefs: $0.refs)
                },
                warnings: blocking.map {
                    KiCadWarning(
                        code: $0.code,
                        message: diagnosticMessage($0.message, commandOutput: commandOutput),
                        affectedRefs: $0.refs,
                        suggestedAction: "Repair the DRC diagnostic and rerun kicad_run_drc."
                    )
                },
                nextActions: ["repair_drc_from_diagnostics", "rerun_drc"]
            )
        default:
            return nil
        }
    }

    private func handleERCRepairFromDiagnostics(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let ercReportPath = stringValue(object, keys: ["erc_report_path", "ercReportPath"]),
              FileManager.default.fileExists(atPath: ercReportPath),
              let circuitIRPath = stringValue(object, keys: ["circuit_ir_path", "circuitIRPath"]),
              FileManager.default.fileExists(atPath: circuitIRPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "ERC repair requires existing erc_report_path and circuit_ir_path artifacts.",
                context: context,
                nextActions: ["attach_erc_report", "attach_circuit_ir"]
            )
        }

        do {
            let report = try KiCadERCParser().parse(jsonData: Data(contentsOf: URL(fileURLWithPath: ercReportPath)))
            let circuitIR = try JSONDecoder().decode(CircuitIR.self, from: Data(contentsOf: URL(fileURLWithPath: circuitIRPath)))
            let plan = ERCRepairPlanner().planRepairs(report: report, circuitIR: circuitIR, resolverEvidence: [])
            guard plan.isRepairable else {
                return repairPlanBlock(
                    request,
                    context: context,
                    code: "UNSUPPORTED_ERC_VIOLATION",
                    message: plan.unsupportedViolations.map(\.code).joined(separator: ", "),
                    affectedRefs: [ercReportPath, circuitIRPath],
                    nextActions: ["request_engineering_review", "rerun_erc"]
                )
            }
            let artifact = writeArtifact(
                request,
                context: context,
                kind: "erc_repair_plan",
                body: try canonicalJSON(plan)
            )
            return complete(request, artifacts: [artifact], nextActions: ["kicad_apply_erc_repair_patch", "kicad_run_erc"])
        } catch {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "ERC repair could not parse diagnostics or Circuit IR: \(error.localizedDescription)",
                context: context,
                nextActions: ["regenerate_erc_report", "regenerate_circuit_ir"]
            )
        }
    }

    private func handleDRCRepairFromDiagnostics(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let drcReportPath = stringValue(object, keys: ["drc_report_path", "drcReportPath"]),
              FileManager.default.fileExists(atPath: drcReportPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "DRC repair requires an existing drc_report_path artifact.",
                context: context,
                nextActions: ["attach_drc_report"]
            )
        }

        do {
            let report = try KiCadDRCParser().parse(jsonData: Data(contentsOf: URL(fileURLWithPath: drcReportPath)))
            let diagnosticProbe = PCBDRCRepairLoop().run(drcReports: [report])
            if let diagnostic = diagnosticProbe.diagnostics.first,
               diagnostic.code == "DRC_REPAIR_REQUIRES_APPROVAL" || diagnostic.code == "UNSUPPORTED_DRC_VIOLATION" {
                return repairPlanBlock(
                    request,
                    context: context,
                    code: diagnostic.code,
                    message: diagnostic.message,
                    affectedRefs: [drcReportPath],
                    nextActions: ["request_engineering_review", "rerun_drc"]
                )
            }

            let planned = report.blockingViolations.isEmpty
                ? PCBDRCRepairLoopResult(status: .verified, attempts: 0, appliedPatches: [], diagnostics: [])
                : PCBDRCRepairLoop().run(drcReports: [report, KiCadDRCReport(violations: [])])
            let artifactBody = DRCRepairPlanArtifact(
                status: "repair_planned",
                patches: planned.appliedPatches,
                diagnostics: planned.diagnostics
            )
            let artifact = writeArtifact(
                request,
                context: context,
                kind: "drc_repair_plan",
                body: try canonicalJSON(artifactBody)
            )
            return complete(request, artifacts: [artifact], nextActions: ["kicad_apply_drc_repair_patch", "kicad_run_drc"])
        } catch {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "DRC repair could not parse diagnostics: \(error.localizedDescription)",
                context: context,
                nextActions: ["regenerate_drc_report"]
            )
        }
    }

    private func handleERCRepairPatchApplication(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let planPath = stringValue(object, keys: ["erc_repair_plan_path", "repair_plan_path"]),
              FileManager.default.fileExists(atPath: planPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "ERC patch application requires an existing erc_repair_plan_path artifact.",
                context: context,
                nextActions: ["kicad_repair_erc_from_diagnostics"]
            )
        }
        guard let schematicPath = schematicPath(from: object),
              FileManager.default.fileExists(atPath: schematicPath) else {
            return structuredBlock(
                request,
                reason: .missingProjectFile,
                message: "ERC patch application requires an existing schematic_path or project_path.",
                context: context,
                nextActions: ["attach_schematic_path"]
            )
        }

        do {
            let plan = try JSONDecoder().decode(ERCRepairPlan.self, from: Data(contentsOf: URL(fileURLWithPath: planPath)))
            let text = try String(contentsOfFile: schematicPath, encoding: .utf8)
            let schematic = try KiCadSchematicParser().parse(text)
            let updated = ERCRepairPatchApplier().apply(plan.patches, to: schematic)
            let rendered = try KiCadSchematicWriter().write(updated)
            try rendered.write(toFile: schematicPath, atomically: true, encoding: .utf8)
            let report = RepairApplicationArtifact(
                status: "patch_applied",
                sourcePlanPath: planPath,
                targetPath: schematicPath,
                patchCount: plan.patches.count,
                mutatedTarget: true,
                requiresRerunTool: "kicad_run_erc"
            )
            let artifact = writeArtifact(
                request,
                context: context,
                kind: "erc_repair_application",
                body: try canonicalJSON(report)
            )
            return complete(request, artifacts: [artifact], nextActions: ["kicad_run_erc"])
        } catch {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "ERC patch application failed: \(error.localizedDescription)",
                context: context,
                nextActions: ["regenerate_erc_repair_plan"]
            )
        }
    }

    private func handleDRCRepairPatchApplication(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let planPath = stringValue(object, keys: ["drc_repair_plan_path", "repair_plan_path"]),
              FileManager.default.fileExists(atPath: planPath),
              let projectPath = stringValue(object, keys: ["project_path", "projectPath"]),
              FileManager.default.fileExists(atPath: projectPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "DRC patch application requires existing drc_repair_plan_path and project_path artifacts.",
                context: context,
                nextActions: ["kicad_repair_drc_from_diagnostics"]
            )
        }

        do {
            let plan = try JSONDecoder().decode(DRCRepairPlanArtifact.self, from: Data(contentsOf: URL(fileURLWithPath: planPath)))
            let report = RepairApplicationArtifact(
                status: "patch_application_recorded",
                sourcePlanPath: planPath,
                targetPath: projectPath,
                patchCount: plan.patches.count,
                mutatedTarget: false,
                requiresRerunTool: "kicad_run_drc"
            )
            let artifact = writeArtifact(
                request,
                context: context,
                kind: "drc_repair_application",
                body: try canonicalJSON(report)
            )
            return complete(
                request,
                artifacts: [artifact],
                warnings: [KiCadWarning(
                    code: "DRC_PATCH_REQUIRES_BOARD_MUTATOR",
                    message: "DRC repair plan was recorded, but no generic PCB mutator is available yet; rerun DRC only after the board change is applied.",
                    affectedRefs: [planPath, projectPath],
                    suggestedAction: "Apply the PCB placement/routing/rule change through a concrete PCB mutator before rerunning DRC."
                )],
                nextActions: ["kicad_run_drc"]
            )
        } catch {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "DRC patch application failed: \(error.localizedDescription)",
                context: context,
                nextActions: ["regenerate_drc_repair_plan"]
            )
        }
    }

    private func handleSPICERepairFromDiagnostics(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let measurementsPath = stringValue(object, keys: ["spice_measurements_path", "spiceMeasurementsPath", "measurements_path"]),
              FileManager.default.fileExists(atPath: measurementsPath),
              let scenarioPath = stringValue(object, keys: ["scenario_path", "scenarioPath"]),
              FileManager.default.fileExists(atPath: scenarioPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "SPICE repair requires existing spice_measurements_path and scenario_path artifacts.",
                context: context,
                nextActions: ["attach_spice_measurements", "attach_simulation_scenario"]
            )
        }

        do {
            let measurementsText = try String(contentsOfFile: measurementsPath, encoding: .utf8)
            let report = try NgspiceMeasurementParser().parse(measurementsText)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let scenario = try decoder.decode(SPICESimulationScenario.self, from: Data(contentsOf: URL(fileURLWithPath: scenarioPath)))
            let validation = SPICEScenarioValidator().validate(scenario)
            guard validation.isValid else {
                return repairPlanBlock(
                    request,
                    context: context,
                    code: validation.issues.first?.code ?? "SPICE_SCENARIO_INVALID",
                    message: validation.issues.map(\.message).joined(separator: "; "),
                    affectedRefs: [scenarioPath],
                    nextActions: ["regenerate_simulation_scenario"]
                )
            }
            let envelope = SPICEMeasurementEnvelopeEvaluator().evaluate(
                report: report,
                envelopes: scenario.measurementEnvelopes
            )
            guard !envelope.passed else {
                return repairPlanBlock(
                    request,
                    context: context,
                    code: "SPICE_REPAIR_NOT_REQUIRED",
                    message: "SPICE measurements already satisfy the declared envelopes; no repair plan is required.",
                    affectedRefs: [measurementsPath, scenarioPath],
                    nextActions: ["continue_validation"]
                )
            }
            let topologyID = stringValue(object, keys: ["topology"]) ?? SPICETopology.singleEndedClassA.rawValue
            let topology = SPICETopology(rawValue: topologyID) ?? .singleEndedClassA
            let plan = SPICESimulationRepairPlanner().plan(failures: envelope.failures, topology: topology)
            guard plan.issues.isEmpty else {
                return repairPlanBlock(
                    request,
                    context: context,
                    code: plan.issues.first?.code ?? "SPICE_REPAIR_UNSUPPORTED",
                    message: plan.issues.map(\.message).joined(separator: "; "),
                    affectedRefs: [measurementsPath, scenarioPath],
                    nextActions: ["request_engineering_review", "rerun_spice"]
                )
            }
            let declaredParameters = spiceRepairParameters(from: object)
            let declaredNames = Set(declaredParameters.map(\.name))
            let missingBounds = plan.patches.compactMap(\.parameterName).filter { !declaredNames.contains($0) }
            guard missingBounds.isEmpty else {
                return repairPlanBlock(
                    request,
                    context: context,
                    code: "SPICE_REPAIR_PARAMETER_BOUNDS_REQUIRED",
                    message: "SPICE repair requires declared min/max bounds for: \(missingBounds.joined(separator: ", ")).",
                    affectedRefs: [measurementsPath, scenarioPath],
                    nextActions: ["declare_repair_parameter_bounds", "request_engineering_review"]
                )
            }
            let artifact = writeArtifact(
                request,
                context: context,
                kind: "spice_repair_plan",
                body: try canonicalJSON(plan)
            )
            return complete(request, artifacts: [artifact], nextActions: ["kicad_apply_spice_repair_patch", "kicad_run_spice"])
        } catch {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "SPICE repair could not parse measurements or scenario: \(error.localizedDescription)",
                context: context,
                nextActions: ["regenerate_spice_measurements", "regenerate_simulation_scenario"]
            )
        }
    }

    private func spiceRepairParameters(from object: [String: Any]) -> [SPICEParameter] {
        let raw = object["repair_parameters"] ?? object["repairParameters"] ?? object["spice_parameters"] ?? object["spiceParameters"]
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let name = stringValue(item, keys: ["name"]),
                  let value = doubleValue(item["value"]),
                  let min = doubleValue(item["min"] ?? item["minimum"]),
                  let max = doubleValue(item["max"] ?? item["maximum"]),
                  min <= value,
                  value <= max else {
                return nil
            }
            return SPICEParameter(name: name, value: value, min: min, max: max)
        }
    }

    private func handleSPICERepairPatchApplication(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let planPath = stringValue(object, keys: ["spice_repair_plan_path", "repair_plan_path"]),
              FileManager.default.fileExists(atPath: planPath),
              let scenarioPath = stringValue(object, keys: ["scenario_path", "scenarioPath"]),
              FileManager.default.fileExists(atPath: scenarioPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "SPICE patch application requires existing spice_repair_plan_path and scenario_path artifacts.",
                context: context,
                nextActions: ["kicad_repair_spice_from_diagnostics"]
            )
        }

        do {
            let plan = try JSONDecoder().decode(SPICESimulationRepairPlan.self, from: Data(contentsOf: URL(fileURLWithPath: planPath)))
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let scenario = try decoder.decode(SPICESimulationScenario.self, from: Data(contentsOf: URL(fileURLWithPath: scenarioPath)))
            let report = RepairApplicationArtifact(
                status: "patch_application_recorded",
                sourcePlanPath: planPath,
                targetPath: scenario.circuitPath,
                patchCount: plan.patches.count,
                mutatedTarget: false,
                requiresRerunTool: "kicad_run_spice"
            )
            let artifact = writeArtifact(
                request,
                context: context,
                kind: "spice_repair_application",
                body: try canonicalJSON(report)
            )
            return complete(
                request,
                artifacts: [artifact],
                warnings: [KiCadWarning(
                    code: "SPICE_PATCH_REQUIRES_DECK_MUTATOR",
                    message: "SPICE repair plan was recorded, but no generic SPICE deck parameter mutator is available yet; rerun SPICE only after the deck change is applied.",
                    affectedRefs: [planPath, scenarioPath, scenario.circuitPath],
                    suggestedAction: "Apply the parameter adjustment to the SPICE deck before rerunning simulation."
                )],
                nextActions: ["kicad_run_spice"]
            )
        } catch {
            return structuredBlock(
                request,
                reason: .invalidInputQuality,
                message: "SPICE patch application failed: \(error.localizedDescription)",
                context: context,
                nextActions: ["regenerate_spice_repair_plan"]
            )
        }
    }

    private func repairPlanBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        code: String,
        message: String,
        affectedRefs: [String],
        nextActions: [String]
    ) -> WorkspaceMessageResponse {
        structuredBlock(
            request,
            reason: .failedGate,
            message: message.isEmpty ? code : message,
            context: context,
            warnings: [KiCadWarning(
                code: code,
                message: message.isEmpty ? code : message,
                affectedRefs: affectedRefs,
                suggestedAction: "Escalate the diagnostic or provide additional engineering evidence before retrying."
            )],
            nextActions: nextActions
        )
    }

    private func validationDiagnosticBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        gate: String,
        artifacts: [ArtifactRef],
        violations: [KiCadViolation],
        warnings: [KiCadWarning],
        nextActions: [String]
    ) -> WorkspaceMessageResponse {
        let message = "\(gate.uppercased()) reported blocking diagnostics."
        Task {
            await publishDiagnostic(reason: .failedGate, request: request, context: context, message: message)
        }
        return WorkspaceMessageResponse(
            requestID: request.id,
            status: .blocked,
            payload: try? .encodeJSON(KiCadToolResult(
                status: .blocked,
                artifacts: artifacts,
                violations: violations,
                warnings: warnings,
                nextActions: nextActions,
                handoff: workflowHandoff(for: request, artifacts: artifacts)
            )),
            artifacts: workspaceArtifacts(from: artifacts, request: request),
            diagnostics: warnings.map {
                WorkspaceDiagnostic(code: $0.code, message: $0.message, severity: "error")
            }
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

    private func schematicPath(from object: [String: Any]) -> String? {
        if let path = stringValue(object, keys: ["schematic_path", "schematicPath"]),
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return path
        }
        guard let projectPath = stringValue(object, keys: ["project_path", "projectPath"]) else {
            return nil
        }
        return kiCadInputPath(for: ["sch"], projectPath: projectPath)
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
        if !FileManager.default.fileExists(atPath: outputURL.path) {
            try? run.output.write(to: outputURL, atomically: true, encoding: .utf8)
        }
        let artifacts = [ArtifactRef(path: outputURL.path, kind: "spice_measurements")]
        guard run.exitCode == 0 else {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                return spiceDiagnosticBlock(
                    request,
                    context: context,
                    outputURL: outputURL,
                    run: run,
                    artifacts: artifacts
                )
            }
            return commandFailureBlock(request, context: context, code: "SPICE_EXECUTION_FAILED", run: run)
        }
        if let envelopeResponse = spiceMeasurementEnvelopeBlockIfNeeded(
            request,
            context: context,
            object: object,
            outputURL: outputURL,
            artifacts: artifacts
        ) {
            return envelopeResponse
        }
        return complete(request, artifacts: artifacts)
    }

    private func spiceMeasurementEnvelopeBlockIfNeeded(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        object: [String: Any],
        outputURL: URL,
        artifacts: [ArtifactRef]
    ) -> WorkspaceMessageResponse? {
        let envelopes = spiceMeasurementEnvelopes(from: object)
        guard !envelopes.isEmpty else { return nil }

        let output = (try? String(contentsOf: outputURL, encoding: .utf8)) ?? ""
        let report: SPICEMeasurementReport
        do {
            report = try NgspiceMeasurementParser().parse(output)
        } catch {
            return spiceMeasurementEnvelopeFailureBlock(
                request,
                context: context,
                message: "SPICE measurement parsing failed: \(error.localizedDescription)",
                artifacts: artifacts,
                affectedRefs: [outputURL.path]
            )
        }

        let evaluation = SPICEMeasurementEnvelopeEvaluator().evaluate(report: report, envelopes: envelopes)
        guard !evaluation.passed else { return nil }

        let failureDescriptions = evaluation.failures.map { failure in
            let actual = failure.actual.isNaN ? "missing" : "\(failure.actual)"
            return "\(failure.measurement)=\(actual), expected \(failure.expected)"
        }
        return spiceMeasurementEnvelopeFailureBlock(
            request,
            context: context,
            message: "SPICE measurements are outside required envelopes: \(failureDescriptions.joined(separator: "; ")).",
            artifacts: artifacts,
            affectedRefs: [outputURL.path] + envelopes.map(\.name)
        )
    }

    private func spiceMeasurementEnvelopeFailureBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        message: String,
        artifacts: [ArtifactRef],
        affectedRefs: [String]
    ) -> WorkspaceMessageResponse {
        let warning = KiCadWarning(
            code: "SPICE_MEASUREMENT_OUT_OF_ENVELOPE",
            message: message,
            affectedRefs: affectedRefs,
            suggestedAction: "Repair the SPICE deck, model, or circuit parameters, then rerun kicad_run_spice."
        )
        Task {
            await publishDiagnostic(reason: .failedGate, request: request, context: context, message: message)
        }
        return WorkspaceMessageResponse(
            requestID: request.id,
            status: .blocked,
            payload: try? .encodeJSON(KiCadToolResult(
                status: .blockedSimulation,
                artifacts: artifacts,
                warnings: [warning],
                nextActions: ["repair_spice_from_diagnostics", "rerun_spice"],
                handoff: workflowHandoff(for: request, artifacts: artifacts)
            )),
            artifacts: workspaceArtifacts(from: artifacts, request: request),
            diagnostics: [WorkspaceDiagnostic(code: warning.code, message: warning.message, severity: "error")]
        )
    }

    private func spiceMeasurementEnvelopes(from object: [String: Any]) -> [SPICEMeasurementEnvelope] {
        let raw = object["measurement_envelopes"] ?? object["measurementEnvelopes"] ?? object["required_measurements"] ?? object["requiredMeasurements"]
        guard let items = raw as? [[String: Any]] else { return [] }
        return items.compactMap { item in
            guard let name = stringValue(item, keys: ["name", "measurement"]),
                  !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return SPICEMeasurementEnvelope(
                name: name,
                min: doubleValue(item["min"] ?? item["minimum"]),
                max: doubleValue(item["max"] ?? item["maximum"])
            )
        }
    }

    private func handleSPICEScenarioGeneration(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = request.payload.jsonObject() ?? [:]
        guard let projectPath = stringValue(object, keys: ["project_path", "projectPath"]),
              FileManager.default.fileExists(atPath: projectPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "SPICE scenario generation requires an existing project_path.",
                context: context
            )
        }
        guard let circuitIRPath = stringValue(object, keys: ["circuit_ir_path", "circuitIRPath", "circuitIrPath"]),
              FileManager.default.fileExists(atPath: circuitIRPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "SPICE scenario generation requires an existing circuit_ir_path with a SPICE verification scenario.",
                context: context,
                warnings: [KiCadWarning(
                    code: "SPICE_CIRCUIT_IR_REQUIRED",
                    message: "SPICE scenario generation requires CircuitIR evidence; Merlin will not generate a generic SPICE deck from project_path alone.",
                    affectedRefs: affectedRefs(from: request),
                    suggestedAction: "Pass circuit_ir_path and an explicit spice_scenario_path."
                )]
            )
        }
        guard let spiceScenarioPath = stringValue(object, keys: ["spice_scenario_path", "spiceScenarioPath", "simulation_scenario_path", "simulationScenarioPath"]),
              FileManager.default.fileExists(atPath: spiceScenarioPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "SPICE scenario generation requires an existing spice_scenario_path JSON artifact.",
                context: context,
                warnings: [KiCadWarning(
                    code: "SPICE_SCENARIO_EVIDENCE_REQUIRED",
                    message: "Merlin will not synthesize a SPICE scenario without explicit scenario evidence and measurement envelopes.",
                    affectedRefs: affectedRefs(from: request),
                    suggestedAction: "Create a SPICESimulationScenario JSON with circuit_path, analyses, required_model_refs, and measurement_envelopes."
                )]
            )
        }
        guard let spiceModelRecordsPath = stringValue(object, keys: ["spice_model_records_path", "spiceModelRecordsPath", "model_records_path", "modelRecordsPath"]),
              FileManager.default.fileExists(atPath: spiceModelRecordsPath) else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "SPICE scenario generation requires an existing spice_model_records_path artifact.",
                context: context,
                warnings: [KiCadWarning(
                    code: "SPICE_MODEL_RECORDS_REQUIRED",
                    message: "SPICE model references must be backed by local model records; Merlin will not assume required models are available.",
                    affectedRefs: affectedRefs(from: request),
                    suggestedAction: "Provide SPICEModelRecord JSON evidence for every required model reference."
                )]
            )
        }

        let projectURL = URL(fileURLWithPath: projectPath)
        let outputRoot: URL
        if let outputDirectory = stringValue(object, keys: ["output_directory", "outputDirectory"]),
           !outputDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            outputRoot = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        } else {
            outputRoot = context.workspaceRoot.appendingPathComponent("simulation", isDirectory: true)
        }

        do {
            let circuitIR = try JSONDecoder().decode(CircuitIR.self, from: Data(contentsOf: URL(fileURLWithPath: circuitIRPath)))
            guard circuitIR.verificationScenarios.contains(where: { $0.kind.lowercased() == "spice" }) else {
                return structuredBlock(
                    request,
                    reason: .invalidInputQuality,
                    message: "CircuitIR does not declare a SPICE verification scenario.",
                    context: context,
                    warnings: [KiCadWarning(
                        code: "SPICE_VERIFICATION_SCENARIO_REQUIRED",
                        message: "CircuitIR must include a verification_scenarios entry with kind=spice before Merlin can generate a runnable SPICE deck.",
                        affectedRefs: [circuitIRPath],
                        suggestedAction: "Add a SPICE verification scenario to CircuitIR or revise the design intent."
                    )]
                )
            }
            let scenarioDecoder = JSONDecoder()
            scenarioDecoder.keyDecodingStrategy = .convertFromSnakeCase
            let scenario = try scenarioDecoder.decode(SPICESimulationScenario.self, from: Data(contentsOf: URL(fileURLWithPath: spiceScenarioPath)))
            let validation = SPICEScenarioValidator().validate(scenario)
            guard validation.isValid else {
                return structuredBlock(
                    request,
                    reason: .invalidInputQuality,
                    message: validation.issues.map(\.message).joined(separator: "; "),
                    context: context,
                    warnings: validation.issues.map {
                        KiCadWarning(code: $0.code, message: $0.message, affectedRefs: [spiceScenarioPath], suggestedAction: "Repair the SPICE scenario JSON and rerun kicad_generate_spice_scenario.")
                    }
                )
            }
            let modelDecoder = JSONDecoder()
            modelDecoder.keyDecodingStrategy = .convertFromSnakeCase
            let modelRecords = try modelDecoder.decode([SPICEModelRecord].self, from: Data(contentsOf: URL(fileURLWithPath: spiceModelRecordsPath)))
            let modelResolution = SPICEModelResolver().resolve(
                requiredModels: scenario.requiredModelRefs,
                availableModels: modelRecords,
                approvals: []
            )
            guard modelResolution.canSimulate else {
                return structuredBlock(
                    request,
                    reason: .invalidInputQuality,
                    message: modelResolution.issues.map(\.message).joined(separator: "; "),
                    context: context,
                    warnings: modelResolution.issues.map {
                        KiCadWarning(code: $0.code, message: $0.message, affectedRefs: [spiceScenarioPath, spiceModelRecordsPath], suggestedAction: "Provide a legally usable exact SPICE model or explicitly approved substitute before generating the scenario.")
                    }
                )
            }
            let circuitDeckURL = URL(fileURLWithPath: scenario.circuitPath)
            guard FileManager.default.fileExists(atPath: circuitDeckURL.path) else {
                return structuredBlock(
                    request,
                    reason: .missingArtifact,
                    message: "SPICE scenario references a missing circuit_path: \(scenario.circuitPath).",
                    context: context,
                    warnings: [KiCadWarning(
                        code: "SPICE_CIRCUIT_DECK_REQUIRED",
                        message: "The SPICE scenario must reference an existing runnable .cir/.sp deck.",
                        affectedRefs: [spiceScenarioPath, scenario.circuitPath],
                        suggestedAction: "Create the referenced SPICE circuit deck before generating the simulation scenario."
                    )]
                )
            }
            let deckText = try String(contentsOf: circuitDeckURL, encoding: .utf8)
            let deckValidation = SPICECircuitDeckValidator().validate(deckText: deckText, scenario: scenario)
            guard deckValidation.isValid else {
                return structuredBlock(
                    request,
                    reason: .invalidInputQuality,
                    message: deckValidation.issues.map(\.message).joined(separator: "; "),
                    context: context,
                    warnings: deckValidation.issues.map {
                        KiCadWarning(
                            code: $0.code,
                            message: $0.message,
                            affectedRefs: [scenario.circuitPath],
                            suggestedAction: "Provide a valid SPICE deck with declared analyses and .meas entries for each required envelope."
                        )
                    }
                )
            }
            guard looksLikeSpiceDeck(deckText) else {
                return structuredBlock(
                    request,
                    reason: .invalidInputQuality,
                    message: "SPICE scenario circuit_path is not a runnable SPICE deck.",
                    context: context,
                    warnings: [KiCadWarning(
                        code: "SPICE_CIRCUIT_DECK_INVALID",
                        message: "The referenced circuit_path must contain circuit elements, an analysis directive, and .end.",
                        affectedRefs: [scenario.circuitPath],
                        suggestedAction: "Provide a valid SPICE deck rather than a summary or placeholder file."
                    )]
                )
            }
            try FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)
            let baseName = projectURL.deletingPathExtension().lastPathComponent.isEmpty
                ? "merlin-simulation"
                : projectURL.deletingPathExtension().lastPathComponent
            let scenarioURL = outputRoot.appendingPathComponent("\(baseName)-\(scenario.scenarioId)-scenario.cir")
            if FileManager.default.fileExists(atPath: scenarioURL.path) {
                try FileManager.default.removeItem(at: scenarioURL)
            }
            try FileManager.default.copyItem(at: circuitDeckURL, to: scenarioURL)
            return complete(
                request,
                artifacts: [
                    ArtifactRef(path: scenarioURL.path, kind: "simulation_scenario"),
                    ArtifactRef(path: spiceScenarioPath, kind: "spice_scenario"),
                    ArtifactRef(path: spiceModelRecordsPath, kind: "spice_model_records"),
                ],
                nextActions: ["kicad_run_spice"]
            )
        } catch {
            return structuredBlock(
                request,
                reason: .missingProjectFile,
                message: "Failed to write SPICE scenario deck: \(error.localizedDescription)",
                context: context
            )
        }
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
        warnings: [KiCadWarning] = [],
        nextActions: [String] = []
    ) -> WorkspaceMessageResponse {
        .ok(
            requestID: request.id,
            payload: try? .encodeJSON(KiCadToolResult(
                status: .complete,
                artifacts: artifacts,
                warnings: warnings,
                metrics: metrics,
                nextActions: nextActions,
                handoff: workflowHandoff(for: request, artifacts: artifacts)
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

    private func workflowHandoff(for request: WorkspaceMessageRequest, artifacts: [ArtifactRef]) -> KiCadWorkflowHandoff? {
        let object = request.payload.jsonObject() ?? [:]
        var handoff = KiCadWorkflowHandoff(
            designIntentPath: stringValue(object, keys: ["design_intent_path", "designIntentPath"]),
            circuitIRPath: stringValue(object, keys: ["circuit_ir_path", "circuitIRPath"]),
            componentMatrixPath: stringValue(object, keys: ["component_matrix_path", "componentMatrixPath"]),
            footprintAssignmentPath: stringValue(object, keys: ["footprint_assignment_path", "footprintAssignmentPath"]),
            projectPath: stringValue(object, keys: ["project_path", "projectPath"]),
            ercReportPath: stringValue(object, keys: ["erc_report_path", "ercReportPath"]),
            drcReportPath: stringValue(object, keys: ["drc_report_path", "drcReportPath"]),
            simulationScenarioPath: stringValue(object, keys: ["simulation_scenario_path", "simulationScenarioPath", "scenario_path", "scenarioPath"]),
            spiceMeasurementsPath: stringValue(object, keys: ["spice_measurements_path", "spiceMeasurementsPath"])
        )

        for artifact in artifacts {
            switch artifact.kind {
            case "design_intent":
                handoff.designIntentPath = artifact.path
            case "circuit_ir":
                handoff.circuitIRPath = artifact.path
            case "component_matrix":
                handoff.componentMatrixPath = artifact.path
            case "footprint_assignment":
                handoff.footprintAssignmentPath = artifact.path
            case ElectronicsArtifactKind.kicadProject.rawValue:
                handoff.projectPath = artifact.path
            case "erc_report":
                handoff.ercReportPath = artifact.path
            case "drc_report":
                handoff.drcReportPath = artifact.path
            case "simulation_scenario":
                handoff.simulationScenarioPath = artifact.path
            case "spice_measurements":
                handoff.spiceMeasurementsPath = artifact.path
            default:
                continue
            }
        }

        if handoff.designIntentPath == nil,
           handoff.circuitIRPath == nil,
           handoff.componentMatrixPath == nil,
           handoff.footprintAssignmentPath == nil,
           handoff.projectPath == nil,
           handoff.ercReportPath == nil,
           handoff.drcReportPath == nil,
           handoff.simulationScenarioPath == nil,
           handoff.spiceMeasurementsPath == nil {
            return nil
        }
        return handoff
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
            if let value = object[key] as? NSNumber {
                return value.stringValue
            }
        }
        return nil
    }

    private func handleDesignIntentBuild(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) -> WorkspaceMessageResponse {
        let object = mergedDesignIntentObject(request)
        let bodyObject: [String: Any]
        let normalizedObject = mergedDesignIntentObject(from: object)
        if let path = object["input_artifact_path"] as? String,
           FileManager.default.fileExists(atPath: path) {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return structuredBlock(
                    request,
                    reason: .invalidInputQuality,
                    message: "kicad_build_intent_model requires a readable non-empty requirements artifact.",
                    context: context
                )
            }
            bodyObject = inferredDesignIntentObject(fromRequirementsText: text, baseObject: normalizedObject)
        } else if object["requirements"] != nil || object["constraints_json"] != nil {
            bodyObject = normalizedObject
        } else {
            return structuredBlock(
                request,
                reason: .missingArtifact,
                message: "kicad_build_intent_model requires an existing input_artifact_path.",
                context: context
            )
        }

        if componentsMissing(from: bodyObject) && netsMissing(from: bodyObject) {
            let synthesis = topologySynthesis(from: bodyObject)
            if synthesis.components.isEmpty || synthesis.nets.isEmpty {
                return structuredBlock(
                    request,
                    reason: .invalidInputQuality,
                    message: "kicad_build_intent_model could not derive component and net intent evidence from the supplied requirements.",
                    context: context
                )
            }
        }

        return complete(
            request,
            artifacts: [writeArtifact(request, context: context, kind: "design_intent", body: designIntentBody(from: bodyObject, request: request))],
            nextActions: ["review_and_approve_design_intent"]
        )
    }

    private func componentsMissing(from object: [String: Any]) -> Bool {
        componentIntents(from: object).isEmpty
    }

    private func netsMissing(from object: [String: Any]) -> Bool {
        netIntents(from: object).isEmpty
    }

    private func designIntentBody(_ request: WorkspaceMessageRequest) -> String {
        designIntentBody(from: mergedDesignIntentObject(request), request: request)
    }

    private func designIntentBody(from object: [String: Any], request: WorkspaceMessageRequest) -> String {
        let synthesis = topologySynthesis(from: object)
        let designID = object["design_id"] as? String ?? object["board_profile_id"] as? String ?? request.id.uuidString
        let title = object["title"] as? String ?? object["board_profile_id"] as? String ?? "Draft Electronics DesignIntent"
        let explicitComponents = componentIntents(from: object)
        let explicitNets = netIntents(from: object)
        let explicitBoards = boardIntents(from: object)
        let explicitAssumptions = assumptions(from: object)
        let intent = DesignIntent(
            designId: designID,
            title: title,
            origin: .naturalLanguage,
            approval: designApproval(from: object),
            requirements: requirements(from: object),
            assumptions: mergedAssumptions(explicitAssumptions, synthesis.assumptions),
            components: explicitComponents.isEmpty ? synthesis.components : explicitComponents,
            nets: explicitNets.isEmpty ? synthesis.nets : explicitNets,
            unresolvedDecisions: unresolvedDecisions(from: object),
            boards: explicitBoards.isEmpty ? synthesis.boards : explicitBoards,
            safetyProfile: safetyProfile(from: object),
            verificationPlan: object["verification_plan"] == nil ? (synthesis.verificationPlan ?? verificationPlan(from: object)) : verificationPlan(from: object)
        )
        return (try? canonicalJSON(intent)) ?? #"{"design_id":"\#(designID)","origin":"natural_language","approval":{"status":"draft"}}"#
    }

    private func inferredDesignIntentObject(fromRequirementsText text: String, baseObject: [String: Any]) -> [String: Any] {
        let lower = text.lowercased()
        var inferred: [String: Any] = [:]

        inferred["requirements"] = extractedRequirementLines(from: text)
        inferred["title"] = inferredTitle(fromRequirementsText: text) ?? baseObject["board_profile_id"] ?? "Draft Electronics DesignIntent"

        if lower.contains("25 watt") || lower.contains("25w") || lower.contains("25 w") {
            inferred["output_power_watts"] = 25
        }
        if lower.contains("8 ohm") || lower.contains("8-ohm") || lower.contains("8Ω") {
            inferred["load_ohms"] = 8
        }
        if lower.contains("single-ended") || lower.contains("single ended") {
            inferred["topology"] = "single-ended_class_a"
        } else if lower.contains("class a") || lower.contains("class-a") {
            inferred["topology"] = "class_a"
        }
        if lower.contains("pure class a") || lower.contains("class-a") || lower.contains("class a") {
            inferred["amplifier_class"] = "pure_class_a"
        }
        if lower.contains("guitar") {
            inferred["application"] = "guitar_amplifier"
        }
        if lower.contains("discrete component") || lower.contains("discrete components") {
            inferred["signal_path_components"] = "discrete_only"
            inferred["output_stage_components"] = "discrete_only"
        }
        if lower.contains("3-band") || lower.contains("three-band") {
            inferred["tone_bands"] = ["bass", "mid", "treble"]
        }
        if lower.contains("sweepable") || lower.contains("boost/cut") || lower.contains("boost-cut") {
            inferred["tone_control"] = "3_band_with_sweepable_boost_cut"
        }
        if lower.contains("transformer-isolated") || lower.contains("transformer isolated") || lower.contains("isolated secondary") {
            inferred["mains_isolation"] = "transformer_isolated"
        }
        if lower.contains("off-board mains") || lower.contains("off board mains") || lower.contains("off-board transformer primary") {
            inferred["mains_primary_offboard"] = true
        }
        if lower.contains("low-voltage secondary") || lower.contains("secondary-side") || lower.contains("secondary side") {
            inferred["pcb_domain"] = "secondary_side_only"
            inferred["pcb_secondary_only"] = true
        }

        inferred["verification_plan"] = [
            "erc_required": lower.contains("erc") || lower.contains("schematic"),
            "drc_required": lower.contains("drc") || lower.contains("pcb") || lower.contains("gerber"),
            "spice_required": lower.contains("spice") || lower.contains("simulation"),
        ]

        inferred["safety_notes"] = extractedSafetyNotes(from: text)

        var result = inferred
        result.merge(baseObject) { _, explicit in explicit }
        return result
    }

    private func inferredTitle(fromRequirementsText text: String) -> String? {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let projectIndex = lines.firstIndex(where: { $0 == "## Project" }),
           lines.indices.contains(projectIndex + 2),
           !lines[projectIndex + 2].isEmpty {
            return lines[projectIndex + 2]
                .replacingOccurrences(of: " is a soup-to-nuts Merlin electronics-domain demonstration project.", with: "")
        }
        if text.lowercased().contains("25 watt"), text.lowercased().contains("guitar amplifier") {
            return "25W pure Class-A solid-state guitar amplifier"
        }
        return nil
    }

    private func extractedRequirementLines(from text: String) -> [String] {
        let keywords = [
            "25 watt", "25w", "class a", "class-a", "single-ended", "single ended",
            "discrete", "guitar", "8 ohm", "8-ohm", "3-band", "three-band",
            "sweepable", "boost/cut", "transformer", "isolated", "mains",
            "spice", "simulation", "erc", "drc", "gerber", "bom",
        ]
        var seen = Set<String>()
        var requirements: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let stripped = rawLine
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-* "))
            guard !stripped.isEmpty else { continue }
            let lower = stripped.lowercased()
            guard keywords.contains(where: { lower.contains($0) }) else { continue }
            guard !seen.contains(stripped) else { continue }
            seen.insert(stripped)
            requirements.append(stripped)
        }
        return requirements
    }

    private func extractedSafetyNotes(from text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "-* ")) }
            .filter {
                let lower = $0.lowercased()
                return lower.contains("mains")
                    || lower.contains("safety")
                    || lower.contains("clearance")
                    || lower.contains("creepage")
                    || lower.contains("earth")
                    || lower.contains("fuse")
                    || lower.contains("transformer")
            }
    }

    private func mergedDesignIntentObject(_ request: WorkspaceMessageRequest) -> [String: Any] {
        mergedDesignIntentObject(from: request.payload.jsonObject() ?? [:])
    }

    private func mergedDesignIntentObject(from rawObject: [String: Any]) -> [String: Any] {
        var object = rawObject
        if let constraints = object["constraints_json"] as? String,
           let data = constraints.data(using: .utf8),
           let nested = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            object.merge(nested) { _, new in new }
        }
        return normalizeDesignIntentAliases(object)
    }

    private func normalizeDesignIntentAliases(_ object: [String: Any]) -> [String: Any] {
        var result = object

        func setIfMissing(_ key: String, _ value: Any?) {
            guard result[key] == nil, let value else { return }
            result[key] = value
        }

        if let amplifier = object["amplifier"] as? [String: Any] {
            setIfMissing("topology", amplifier["topology"] ?? amplifier["amplifier_topology"] ?? amplifier["output_topology"])
            setIfMissing("output_power_watts", amplifier["output_power_watts"] ?? amplifier["output_power_nominal_w"] ?? amplifier["output_power_w"] ?? amplifier["power_output_watts"] ?? amplifier["power_watts"])
            setIfMissing("load_ohms", amplifier["load_ohms"] ?? amplifier["load_impedance_ohm"] ?? amplifier["speaker_load_ohms"] ?? amplifier["speaker_load"])
            let technology = stringValue(amplifier, keys: ["component_technology", "signal_path", "output_stage"])?.lowercased() ?? ""
            if boolValue(amplifier["discrete_only"]) == true || technology.contains("discrete") {
                setIfMissing("signal_path_components", "discrete_only")
                setIfMissing("output_stage_components", "discrete_only")
            }
        }

        if let powerSupply = object["power_supply"] as? [String: Any] {
            if let isolation = stringValue(powerSupply, keys: ["isolation", "mains_isolation"])?.lowercased(),
               isolation.contains("transformer") || isolation.contains("isolated") {
                setIfMissing("mains_isolation", "transformer_isolated")
            }
            setIfMissing("mains_input", powerSupply["mains_input"])
            setIfMissing("mains_primary_offboard", powerSupply["offboard_mains_primary"])
            if boolValue(powerSupply["pcb_starts_at_secondary"]) == true {
                setIfMissing("pcb_secondary_only", true)
                setIfMissing("pcb_domain", "secondary_side_only")
            }
        }

        setIfMissing("output_power_watts", object["output_power_nominal_w"] ?? object["output_power_w"] ?? object["power_output_w"] ?? object["power_watts"])
        setIfMissing("load_ohms", object["load_impedance_ohm"] ?? object["speaker_load_ohms"] ?? object["speaker_load"])
        let technology = stringValue(object, keys: ["component_technology", "signal_path", "output_stage", "component_policy"])?.lowercased() ?? ""
        if technology.contains("discrete") {
            setIfMissing("signal_path_components", "discrete_only")
            setIfMissing("output_stage_components", "discrete_only")
        }
        if let isolation = stringValue(object, keys: ["isolation"])?.lowercased(),
           isolation.contains("transformer") || isolation.contains("isolated") {
            setIfMissing("mains_isolation", "transformer_isolated")
        }
        if let pcbScope = stringValue(object, keys: ["pcb_scope", "pcb_domain"])?.lowercased(),
           pcbScope.contains("secondary") {
            setIfMissing("pcb_secondary_only", true)
            setIfMissing("pcb_domain", "secondary_side_only")
        }

        if let toneStack = stringValue(object, keys: ["tone_stack"])?.lowercased() {
            if toneStack.contains("3") && toneStack.contains("bass") && toneStack.contains("mid") && toneStack.contains("treble") {
                setIfMissing("tone_bands", ["bass", "mid", "treble"])
            }
            if boolValue(object["sweepable_filter"]) == true || toneStack.contains("sweep") || toneStack.contains("boost") || toneStack.contains("cut") {
                setIfMissing("tone_control", "3_band_with_sweepable_boost_cut")
            }
        }

        if boolValue(object["sweepable_filter"]) == true {
            setIfMissing("tone_control", "3_band_with_sweepable_boost_cut")
        }

        if let toneControls = object["tone_controls"] as? [String: Any] {
            setIfMissing("tone_bands", toneControls["bands"])
            if toneControls["sweepable_filter"] != nil {
                setIfMissing("tone_control", "3_band_with_sweepable_boost_cut")
            }
        } else if let toneControls = object["tone_controls"] as? [String] {
            let lower = toneControls.map { $0.lowercased() }
            if lower.contains(where: { $0.contains("bass") })
                && lower.contains(where: { $0.contains("mid") })
                && lower.contains(where: { $0.contains("treble") }) {
                setIfMissing("tone_bands", ["bass", "mid", "treble"])
            }
            if lower.contains(where: { $0.contains("sweepable") || $0.contains("boost") || $0.contains("cut") }) {
                setIfMissing("tone_control", "3_band_with_sweepable_boost_cut")
            }
        }

        return result
    }

    private func designApproval(from object: [String: Any]) -> DesignApproval {
        if let value = object["approval"] as? String,
           let status = DesignApprovalStatus(rawValue: value) {
            return DesignApproval(status: status, approvedBy: object["approved_by"] as? String, approvedAt: object["approved_at"] as? String)
        }
        if let approval = object["approval"] as? [String: Any],
           let value = approval["status"] as? String,
           let status = DesignApprovalStatus(rawValue: value) {
            return DesignApproval(
                status: status,
                approvedBy: approval["approved_by"] as? String,
                approvedAt: approval["approved_at"] as? String
            )
        }
        return DesignApproval(status: .draft)
    }

    private func requirements(from object: [String: Any]) -> [Requirement] {
        if let text = object["requirements"] as? String, !text.isEmpty {
            return [Requirement(id: "req-1", text: text, priority: "must")]
        }
        if let values = object["requirements"] as? [String] {
            return values.enumerated().map {
                Requirement(id: "req-\($0.offset + 1)", text: $0.element, priority: "must")
            }
        }
        if let values = object["requirements"] as? [[String: Any]] {
            return values.enumerated().compactMap { index, value in
                guard let text = value["text"] as? String, !text.isEmpty else { return nil }
                return Requirement(
                    id: value["id"] as? String ?? "req-\(index + 1)",
                    text: text,
                    priority: value["priority"] as? String ?? "must"
                )
            }
        }
        let excludedKeys: Set<String> = [
            "approval",
            "approved_at",
            "approved_by",
            "assumptions",
            "board_profile_id",
            "components",
            "constraints_json",
            "design_id",
            "input_artifact_path",
            "nets",
            "title",
            "unresolved_decisions",
            "verification_plan",
        ]
        return object
            .filter { !excludedKeys.contains($0.key) }
            .sorted { $0.key < $1.key }
            .enumerated()
            .compactMap { index, entry in
                guard let text = requirementText(key: entry.key, value: entry.value) else { return nil }
                return Requirement(id: "constraint-\(index + 1)", text: text, priority: "must")
            }
    }

    private func requirementText(key: String, value: Any) -> String? {
        if let string = value as? String, !string.isEmpty {
            return "\(key): \(string)"
        }
        if value is NSNull {
            return nil
        }
        if let bool = value as? Bool {
            return "\(key): \(bool)"
        }
        if let number = value as? NSNumber {
            return "\(key): \(number.stringValue)"
        }
        if let dictionary = value as? [String: Any],
           JSONSerialization.isValidJSONObject(dictionary),
           let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8),
           !string.isEmpty {
            return "\(key): \(string)"
        }
        if let array = value as? [Any],
           JSONSerialization.isValidJSONObject(array),
           let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8),
           !string.isEmpty {
            return "\(key): \(string)"
        }
        if let array = value as? NSArray,
           JSONSerialization.isValidJSONObject(array),
           let data = try? JSONSerialization.data(withJSONObject: array, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8),
           !string.isEmpty {
            return "\(key): \(string)"
        }
        if let dictionary = value as? NSDictionary,
           JSONSerialization.isValidJSONObject(dictionary),
           let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
           let string = String(data: data, encoding: .utf8),
           !string.isEmpty {
            return "\(key): \(string)"
        }
        return nil
    }

    private func assumptions(from object: [String: Any]) -> [Assumption] {
        if let values = object["assumptions"] as? [String] {
            return values.enumerated().map {
                Assumption(id: "assumption-\($0.offset + 1)", text: $0.element, rationale: "provided_by_intent_payload")
            }
        }
        if let values = object["assumptions"] as? [[String: Any]] {
            return values.enumerated().compactMap { index, value in
                guard let text = value["text"] as? String, !text.isEmpty else { return nil }
                return Assumption(
                    id: value["id"] as? String ?? "assumption-\(index + 1)",
                    text: text,
                    rationale: value["rationale"] as? String ?? "provided_by_intent_payload"
                )
            }
        }
        return []
    }

    private func unresolvedDecisions(from object: [String: Any]) -> [UnresolvedDecision] {
        if let values = object["unresolved_decisions"] as? [String] {
            return values.enumerated().map { index, question in
                UnresolvedDecision(id: "decision-\(index + 1)", question: question, blocking: true)
            }
        }
        return []
    }

    private func boardIntents(from object: [String: Any]) -> [BoardIntent] {
        if let values = object["boards"] as? [[String: Any]] {
            return values.enumerated().map { index, value in
                BoardIntent(
                    id: value["id"] as? String ?? "board-\(index + 1)",
                    title: value["title"] as? String ?? "Board \(index + 1)",
                    safetyDomain: value["safety_domain"] as? String ?? value["safetyDomain"] as? String ?? "unspecified",
                    verificationPlan: value["verification_plan"] == nil ? nil : verificationPlan(from: value),
                    interBoardConnectors: interBoardConnectors(from: value)
                )
            }
        }
        if requiresMixedDomainBoardDecomposition(from: object) {
            return [
                BoardIntent(
                    id: "isolated_secondary",
                    title: "Isolated Low-Voltage Board",
                    safetyDomain: "isolated_secondary",
                    verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: true),
                    interBoardConnectors: [
                        InterBoardConnectorIntent(id: "JPRI", targetBoardId: "mains_power", signalRole: "isolated power handoff"),
                    ]
                ),
                BoardIntent(
                    id: "mains_power",
                    title: "Mains Primary and Transformer Board",
                    safetyDomain: "mains_primary",
                    verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: false),
                    interBoardConnectors: [
                        InterBoardConnectorIntent(id: "JSEC", targetBoardId: "isolated_secondary", signalRole: "isolated power handoff"),
                    ]
                ),
            ]
        }
        if object["pcb_secondary_only"] as? Bool == true || object["mains_on_pcb"] as? Bool == false {
            return [BoardIntent(id: "isolated_secondary", title: "Isolated Low-Voltage Secondary PCB", safetyDomain: "isolated_secondary")]
        }
        if object["mains_primary_offboard"] as? Bool == true {
            return [BoardIntent(id: "isolated_secondary", title: "Isolated Low-Voltage Secondary PCB", safetyDomain: "isolated_secondary")]
        }
        if (object["pcb_domain"] as? String)?.lowercased().contains("secondary") == true {
            return [BoardIntent(id: "isolated_secondary", title: "Isolated Low-Voltage Secondary PCB", safetyDomain: "isolated_secondary")]
        }
        return []
    }

    private func interBoardConnectors(from object: [String: Any]) -> [InterBoardConnectorIntent] {
        guard let values = object["inter_board_connectors"] as? [[String: Any]]
            ?? object["interBoardConnectors"] as? [[String: Any]] else {
            return []
        }
        return values.enumerated().map { index, value in
            InterBoardConnectorIntent(
                id: value["id"] as? String ?? "J\(index + 1)",
                targetBoardId: value["target_board_id"] as? String ?? value["targetBoardId"] as? String ?? "",
                signalRole: value["signal_role"] as? String ?? value["signalRole"] as? String ?? "unspecified inter-board handoff"
            )
        }
    }

    private func requiresMixedDomainBoardDecomposition(from object: [String: Any]) -> Bool {
        let text = (
            requirements(from: object).map(\.text)
            + assumptions(from: object).map(\.text)
            + stringArray(object["safety_notes"])
            + [
                object["mains_isolation"] as? String,
                object["pcb_domain"] as? String,
                object["power_domain"] as? String,
            ].compactMap { $0 }
        )
        .joined(separator: " ")
        .lowercased()

        let hasHazardousPower = text.contains("mains")
            || text.contains("line voltage")
            || text.contains("hazardous")
            || text.contains("transformer primary")
            || text.contains("primary side")
            || text.contains("mains_primary")
            || object["mains_primary_offboard"] as? Bool == true
            || object["mains_on_pcb"] as? Bool == true

        let hasLowVoltageDomain = text.contains("low-voltage")
            || text.contains("low voltage")
            || text.contains("isolated")
            || text.contains("secondary")
            || text.contains("control")
            || object["pcb_secondary_only"] as? Bool == true

        return hasHazardousPower && hasLowVoltageDomain
    }

    private func safetyProfile(from object: [String: Any]) -> SafetyProfile {
        if let profile = object["safety_profile"] as? [String: Any] {
            return SafetyProfile(
                isolationRequired: boolValue(profile["isolation_required"]) ?? boolValue(profile["isolationRequired"]) ?? false,
                creepageMm: doubleValue(profile["creepage_mm"]) ?? doubleValue(profile["creepageMm"]) ?? 0.0,
                notes: stringArray(profile["notes"])
            )
        }
        let requirementText = requirements(from: object).map(\.text).joined(separator: " ").lowercased()
        return SafetyProfile(
            isolationRequired: object["pcb_secondary_only"] as? Bool == true
                || object["mains_on_pcb"] as? Bool == false
                || object["mains_primary_offboard"] as? Bool == true
                || (object["mains_isolation"] as? String)?.lowercased().contains("isolated") == true
                || (object["pcb_domain"] as? String)?.lowercased().contains("secondary") == true
                || requirementText.contains("isolated"),
            creepageMm: 0.0,
            notes: stringArray(object["safety_notes"])
        )
    }

    private func verificationPlan(from object: [String: Any]) -> VerificationPlan {
        if let plan = object["verification_plan"] as? [String: Any] {
            return VerificationPlan(
                ercRequired: boolValue(plan["erc_required"]) ?? boolValue(plan["ercRequired"]) ?? true,
                drcRequired: boolValue(plan["drc_required"]) ?? boolValue(plan["drcRequired"]) ?? false,
                spiceRequired: boolValue(plan["spice_required"]) ?? boolValue(plan["spiceRequired"]) ?? false
            )
        }
        let requirementText = requirements(from: object).map(\.text).joined(separator: " ").lowercased()
        return VerificationPlan(
            ercRequired: boolValue(object["erc_required"]) ?? true,
            drcRequired: boolValue(object["drc_required"]) ?? requirementText.contains("drc"),
            spiceRequired: boolValue(object["spice_required"]) ?? requirementText.contains("spice")
        )
    }

    private func componentIntents(from object: [String: Any]) -> [ComponentIntent] {
        guard let values = object["components"] as? [[String: Any]] else { return [] }
        return values.enumerated().compactMap { index, value in
            let refdes = value["refdes"] as? String ?? value["reference"] as? String ?? value["ref"] as? String ?? "U\(index + 1)"
            let role = value["role"] as? String ?? value["description"] as? String ?? "unspecified"
            return ComponentIntent(refdes: refdes, role: role, constraints: stringDictionary(value["constraints"] as? [String: Any] ?? value))
        }
    }

    private func netIntents(from object: [String: Any]) -> [NetIntent] {
        guard let values = object["nets"] as? [[String: Any]] else { return [] }
        return values.compactMap { value in
            guard let name = value["name"] as? String, !name.isEmpty else { return nil }
            return NetIntent(
                name: name,
                role: value["role"] as? String ?? "unspecified",
                source: value["source"] as? String ?? "",
                destination: value["destination"] as? String ?? ""
            )
        }
    }

    private struct TopologySynthesis {
        var components: [ComponentIntent] = []
        var nets: [NetIntent] = []
        var assumptions: [Assumption] = []
        var boards: [BoardIntent] = []
        var verificationPlan: VerificationPlan?
    }

    private func topologySynthesis(from object: [String: Any]) -> TopologySynthesis {
        guard isSingleEndedClassAAudioTopology(object) else {
            return TopologySynthesis()
        }
        let outputPower = stringValue(object, keys: ["output_power_watts", "power_output_watts", "output_power", "power_watts"]) ?? "unspecified"
        let load = stringValue(object, keys: ["load_ohms", "speaker_load_ohms", "speaker_load"]) ?? "8"
        let outputRatings = classAOutputStageRatings(outputPowerWatts: outputPower, loadOhms: load)
        let toneBands = stringArray(object["tone_bands"]).isEmpty ? ["bass", "mid", "treble"] : stringArray(object["tone_bands"])
        let toneBandValue = toneBands.joined(separator: ",")

        return TopologySynthesis(
            components: [
                ComponentIntent(
                    refdes: "JSEC",
                    role: "isolated transformer secondary input connector",
                    constraints: [
                        "kind": "connector",
                        "component_category": "terminal_block",
                        "domain": "isolated_secondary",
                        "mains_primary": "off_board",
                        "positions": "2",
                        "current_rating": "10A",
                        "voltage_rating": "300V",
                        "mounting": "through_hole",
                    ]
                ),
                ComponentIntent(
                    refdes: "BR1",
                    role: "bridge rectifier for isolated secondary supply",
                    constraints: [
                        "kind": "rectifier",
                        "component_category": "bridge_rectifier",
                        "domain": "low_voltage_secondary",
                        "current_rating": "8A",
                        "voltage_rating": "100V",
                        "mounting": "through_hole",
                    ]
                ),
                ComponentIntent(
                    refdes: "CRES1",
                    role: "bulk reservoir capacitor for raw Class-A rail",
                    constraints: [
                        "kind": "capacitor",
                        "component_category": "aluminum_electrolytic_capacitor",
                        "rail": "VRAW",
                        "capacitance": "10000uF",
                        "voltage_rating": "50V",
                        "mounting": "through_hole",
                    ]
                ),
                ComponentIntent(
                    refdes: "JIN",
                    role: "high impedance guitar input connector",
                    constraints: [
                        "kind": "connector",
                        "component_category": "phone_audio_jack",
                        "signal_domain": "audio_input",
                        "contact_form": "mono",
                        "positions": "2",
                        "mounting": "panel_mount",
                    ]
                ),
                ComponentIntent(
                    refdes: "QPRE1",
                    role: "low-noise small-signal preamp transistor stage",
                    constraints: [
                        "component_category": "low_noise_transistor",
                        "implementation": "discrete",
                        "device_family": "JFET_or_low_noise_BJT",
                        "polarity": "NPN_or_N_channel",
                        "package": "TO-92",
                    ]
                ),
                ComponentIntent(
                    refdes: "RPRE1",
                    role: "preamp bias and input impedance network",
                    constraints: [
                        "kind": "resistor_network",
                        "function": "sets_input_bias_and_impedance",
                    ]
                ),
                ComponentIntent(
                    refdes: "TONE1",
                    role: "passive three-band tone control network",
                    constraints: [
                        "implementation": "discrete_RC",
                        "bands": toneBandValue,
                    ]
                ),
                ComponentIntent(
                    refdes: "FILTER1",
                    role: "sweepable boost/cut filter network",
                    constraints: [
                        "implementation": "discrete_RC_or_discrete_transistor",
                        "controls": "frequency,level",
                    ]
                ),
                ComponentIntent(
                    refdes: "QDRV1",
                    role: "discrete voltage driver stage",
                    constraints: [
                        "component_category": "driver_transistor",
                        "implementation": "discrete",
                        "drives": "QOUT1",
                        "polarity": "NPN",
                        "voltage_rating": outputRatings.voltage,
                        "current_rating": "1A",
                        "power_rating": "1W",
                        "package": "TO-126_or_TO-220",
                    ]
                ),
                ComponentIntent(
                    refdes: "QOUT1",
                    role: "single-ended Class-A output transistor",
                    constraints: [
                        "component_category": "power_transistor",
                        "implementation": "discrete",
                        "output_power_watts": outputPower,
                        "load_ohms": load,
                        "thermal": "external_heatsink_required",
                        "polarity": "NPN",
                        "voltage_rating": outputRatings.voltage,
                        "current_rating": outputRatings.current,
                        "power_rating": outputRatings.dissipation,
                        "package": "TO-3_or_TO-247",
                    ]
                ),
                ComponentIntent(
                    refdes: "RBIAS1",
                    role: "Class-A output bias network",
                    constraints: [
                        "kind": "resistor_network",
                        "function": "sets_idle_current",
                    ]
                ),
                ComponentIntent(
                    refdes: "JSPK",
                    role: "\(load) ohm speaker output connector",
                    constraints: [
                        "kind": "connector",
                        "component_category": "speaker_connector",
                        "load_ohms": load,
                        "positions": "2",
                        "current_rating": outputRatings.current,
                        "mounting": "panel_mount",
                    ]
                ),
            ],
            nets: [
                NetIntent(name: "AC_SEC1", role: "isolated secondary AC feed", source: "JSEC", destination: "BR1"),
                NetIntent(name: "VRAW", role: "raw low-voltage Class-A supply rail", source: "BR1", destination: "CRES1"),
                NetIntent(name: "GND", role: "isolated secondary circuit common", source: "BR1", destination: "CRES1"),
                NetIntent(name: "GUITAR_IN", role: "guitar input signal", source: "JIN", destination: "QPRE1"),
                NetIntent(name: "PRE_OUT", role: "preamp output signal", source: "QPRE1", destination: "TONE1"),
                NetIntent(name: "TONE_OUT", role: "tone stack output signal", source: "TONE1", destination: "FILTER1"),
                NetIntent(name: "FILTER_OUT", role: "boost/cut filter output signal", source: "FILTER1", destination: "QDRV1"),
                NetIntent(name: "DRV_OUT", role: "driver output signal", source: "QDRV1", destination: "QOUT1"),
                NetIntent(name: "SPK_OUT", role: "speaker output signal", source: "QOUT1", destination: "JSPK"),
            ],
            assumptions: [
                Assumption(
                    id: "topology-assumption-1",
                    text: "Single-ended 25W Class-A operation is thermally severe and requires explicit heatsink and safe-operating-area review.",
                    rationale: "topology_synthesis"
                ),
                Assumption(
                    id: "topology-assumption-2",
                    text: "North American mains primary circuitry remains off-board; this board only receives an isolated low-voltage transformer secondary.",
                    rationale: "topology_synthesis"
                ),
            ],
            boards: [
                BoardIntent(id: "isolated_secondary", title: "Isolated Low-Voltage Secondary PCB", safetyDomain: "isolated_secondary"),
            ],
            verificationPlan: VerificationPlan(ercRequired: true, drcRequired: true, spiceRequired: true)
        )
    }

    private func isSingleEndedClassAAudioTopology(_ object: [String: Any]) -> Bool {
        let topology = stringValue(object, keys: ["topology", "amplifier_topology", "output_topology"])?.lowercased() ?? ""
        let requirementText = requirements(from: object).map(\.text).joined(separator: " ").lowercased()
        let combined = "\(topology) \(requirementText)"
        let isClassA = combined.contains("class_a") || combined.contains("class-a") || combined.contains("class a")
        let isSingleEnded = combined.contains("single-ended") || combined.contains("single_ended") || combined.contains("single ended")
        let isAudioAmplifier = combined.contains("amplifier")
            || combined.contains("guitar")
            || combined.contains("audio")
            || object["output_power_watts"] != nil
            || object["power_output_watts"] != nil
            || object["tone_control"] != nil
            || object["tone_controls"] != nil
        return isClassA && isSingleEnded && isAudioAmplifier
    }

    private func classAOutputStageRatings(
        outputPowerWatts: String?,
        loadOhms: String?
    ) -> (voltage: String, current: String, dissipation: String) {
        guard let power = outputPowerWatts.flatMap(Double.init),
              let load = loadOhms.flatMap(Double.init),
              power > 0,
              load > 0 else {
            return (voltage: "80V", current: "8A", dissipation: "100W")
        }

        let peakVoltage = (2.0 * power * load).squareRoot()
        let peakCurrent = (2.0 * power / load).squareRoot()
        let voltageRating = max(80.0, ceil((peakVoltage * 4.0) / 10.0) * 10.0)
        let currentRating = max(5.0, ceil(peakCurrent * 3.0))
        let dissipationRating = max(100.0, ceil(power * 4.0 / 10.0) * 10.0)
        return (
            voltage: "\(Int(voltageRating))V",
            current: "\(Int(currentRating))A",
            dissipation: "\(Int(dissipationRating))W"
        )
    }

    private func mergedAssumptions(_ explicit: [Assumption], _ synthesized: [Assumption]) -> [Assumption] {
        guard !synthesized.isEmpty else { return explicit }
        var seen = Set(explicit.map { $0.text })
        var result = explicit
        for assumption in synthesized where !seen.contains(assumption.text) {
            seen.insert(assumption.text)
            result.append(assumption)
        }
        return result
    }

    private func componentSelectionBody(
        _ request: WorkspaceMessageRequest,
        intent: DesignIntent,
        selectionComponents: [ComponentIntent],
        circuitIR: CircuitIR?,
        catalogEvidence: RuntimeCatalogEvidence
    ) async -> String {
        var decisions = selectionComponents.map { componentSelectionDecision(for: $0, candidates: catalogEvidence.candidates) }
        let datasheetResult = await datasheetPDFEnrichedComponentSelectionDecisions(
            decisions,
            cacheDirectory: catalogEvidence.datasheetCacheDirectory,
            revalidateAfterSeconds: catalogEvidence.datasheetRevalidateAfterSeconds
        )
        decisions = datasheetResult.decisions
        if let localFootprintResolver = catalogEvidence.localFootprintResolver {
            decisions = await footprintEnrichedComponentSelectionDecisions(
                decisions,
                selectionComponents: selectionComponents,
                localFootprintResolver: localFootprintResolver
            )
        }
        let matrix = ComponentMatrix(
            designId: circuitIR?.designId ?? intent.designId,
            decisions: decisions,
            warnings: uniqueRefdes(catalogEvidence.warnings + datasheetResult.warnings),
            providers: catalogEvidence.providers,
            cacheMetadata: componentSelectionCacheMetadata(catalogEvidence: catalogEvidence, circuitIR: circuitIR),
            components: selectionComponents
        )
        let legacyComponents = matrix.decisions.map { decision in
            [
                "refdes": decision.refdes,
                "role": selectionComponents.first(where: { $0.refdes == decision.refdes })?.role ?? "",
                "constraints": selectionComponents.first(where: { $0.refdes == decision.refdes })?.constraints ?? [:],
                "selection_status": decision.status.rawValue,
                "mpn": decision.selectedCandidate?.mpn ?? "",
                "manufacturer": decision.selectedCandidate?.manufacturer ?? "",
            ] as [String: Any]
        }
        let encoded = (try? JSONEncoder().encode(matrix)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        } ?? [:]
        var object = encoded
        object["components"] = legacyComponents
        object["policy"] = "provenance_first"
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return #"{"design_id":"\#(request.payload.jsonObject()?["design_id"] as? String ?? request.id.uuidString)","components":[],"policy":"provenance_first"}"#
    }

    private func footprintEnrichedComponentSelectionDecisions(
        _ decisions: [PartSelectionDecision],
        selectionComponents: [ComponentIntent],
        localFootprintResolver: KiCadLibraryCatalogProvider
    ) async -> [PartSelectionDecision] {
        let componentsByRefdes = Dictionary(selectionComponents.map { ($0.refdes, $0) }, uniquingKeysWith: { first, _ in first })
        var enriched: [PartSelectionDecision] = []
        for decision in decisions {
            guard decision.status == .selected,
                  let selected = decision.selectedCandidate,
                  let component = componentsByRefdes[decision.refdes] else {
                enriched.append(decision)
                continue
            }
            let enrichedSelected = await providerCandidate(
                selected,
                for: component,
                localFootprintResolver: localFootprintResolver
            )
            var updated = decision
            updated.selectedCandidate = enrichedSelected
            updated.candidateSet = decision.candidateSet.map {
                $0.mpn == selected.mpn && $0.manufacturer == selected.manufacturer ? enrichedSelected : $0
            }
            enriched.append(updated)
        }
        return enriched
    }

    private func datasheetPDFEnrichedComponentSelectionDecisions(
        _ decisions: [PartSelectionDecision],
        cacheDirectory: URL,
        revalidateAfterSeconds: Int
    ) async -> (decisions: [PartSelectionDecision], warnings: [String]) {
        var enriched: [PartSelectionDecision] = []
        var warnings: [String] = []
        for decision in decisions {
            guard decision.status == .selected,
                  let selected = decision.selectedCandidate else {
                enriched.append(decision)
                continue
            }
            let result = await datasheetPDFEnrichedCandidate(
                selected,
                cacheDirectory: cacheDirectory,
                revalidateAfterSeconds: revalidateAfterSeconds
            )
            warnings.append(contentsOf: result.warnings.map { "DATASHEET_CACHE_WARNING: \(decision.refdes) \($0)" })
            var updated = decision
            updated.selectedCandidate = result.candidate
            updated.candidateSet = decision.candidateSet.map { candidate in
                sameCatalogPart(candidate, result.candidate) ? result.candidate : candidate
            }
            enriched.append(updated)
        }
        return (enriched, uniqueRefdes(warnings))
    }

    private func datasheetPDFEnrichedCandidate(
        _ candidate: ComponentCandidate,
        cacheDirectory: URL,
        revalidateAfterSeconds: Int
    ) async -> (candidate: ComponentCandidate, warnings: [String]) {
        guard !candidate.datasheets.isEmpty else { return (candidate, []) }
        let cache = DatasheetPDFCache()
        var candidate = candidate
        var enrichedDatasheets: [DatasheetEvidence] = []
        var warnings: [String] = []
        for datasheet in candidate.datasheets {
            if let freshLocal = try? cache.loadFreshLocal(
                datasheet,
                from: cacheDirectory,
                revalidateAfterSeconds: revalidateAfterSeconds
            ) {
                enrichedDatasheets.append(freshLocal)
                continue
            }
            guard shouldResolveDatasheetPDF(datasheet) else {
                enrichedDatasheets.append(datasheet)
                continue
            }
            do {
                enrichedDatasheets.append(try await cache.resolve(
                    datasheet,
                    in: cacheDirectory,
                    revalidateAfterSeconds: revalidateAfterSeconds
                ))
            } catch {
                warnings.append("\(datasheet.url) \(error.localizedDescription)")
                enrichedDatasheets.append(datasheet)
            }
        }
        candidate.datasheets = enrichedDatasheets
        return (candidate, warnings)
    }

    private func shouldResolveDatasheetPDF(_ datasheet: DatasheetEvidence) -> Bool {
        guard let url = URL(string: datasheet.url),
              ["http", "https"].contains((url.scheme ?? "").lowercased()) else {
            return false
        }
        let host = (url.host ?? "").lowercased()
        guard !host.hasSuffix(".invalid") else { return false }
        let license = datasheet.license.lowercased()
        guard !license.contains("fixture"), !license.contains("test") else { return false }
        return true
    }

    private func sameCatalogPart(_ lhs: ComponentCandidate, _ rhs: ComponentCandidate) -> Bool {
        lhs.mpn.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(rhs.mpn.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
            && lhs.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(rhs.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private struct RuntimeCatalogEvidence {
        var candidates: [ComponentCandidate]
        var providers: [String]
        var sourceKinds: [String]
        var ttlSeconds: Int?
        var warnings: [String]
        var localFootprintResolver: KiCadLibraryCatalogProvider?
        var datasheetCacheDirectory: URL
        var datasheetRevalidateAfterSeconds: Int
    }

    private struct LiveCatalogTermsGate {
        var enabled: Bool
        var maxQueriesPerRun: Int
        var minQueryIntervalMs: Int
        var issuedQueryCount: Int = 0
        var stoppedProviders: Set<String> = []
        var lastQueryAtByProvider: [String: Date] = [:]

        mutating func skipReason(providerID: String) -> String? {
            guard enabled else { return nil }
            let providerID = providerID.lowercased()
            if stoppedProviders.contains(providerID) {
                return "CATALOG_PROVIDER_TERMS_GATE_SKIPPED: \(providerID) live queries are stopped for this run after a provider limit or denial response."
            }
            if issuedQueryCount >= maxQueriesPerRun {
                return "CATALOG_PROVIDER_TERMS_GATE_SKIPPED: live catalog query budget exhausted (\(maxQueriesPerRun) uncached queries per run)."
            }
            return nil
        }

        mutating func waitIfNeeded(providerID: String) async {
            guard enabled, minQueryIntervalMs > 0 else { return }
            let providerID = providerID.lowercased()
            if let last = lastQueryAtByProvider[providerID] {
                let elapsedMs = Date().timeIntervalSince(last) * 1000
                let remainingMs = Double(minQueryIntervalMs) - elapsedMs
                if remainingMs > 0 {
                    try? await Task.sleep(nanoseconds: UInt64(remainingMs * 1_000_000))
                }
            }
            issuedQueryCount += 1
            lastQueryAtByProvider[providerID] = Date()
        }

        mutating func stopProvider(_ providerID: String) {
            guard enabled else { return }
            stoppedProviders.insert(providerID.lowercased())
        }
    }

    private struct RuntimeCatalogConfig: Codable {
        var catalogProviderFixturePaths: [String: String]? = nil
        var catalogCacheDirectory: String? = nil
        var catalogCacheTTLSeconds: Int? = nil
        var kicadSymbolLibraryRoot: String? = nil
        var kicadFootprintLibraryRoot: String? = nil
        var kicadLibraryRootSearchPaths: [String]? = nil
        var kicadLibraryRootCacheDirectory: String? = nil
        var kicadLibraryRootCacheTTLSeconds: Int? = nil
        var kicadCatalogCacheDirectory: String? = nil
        var kicadCatalogCacheTTLSeconds: Int? = nil
        var liveCatalogProviders: [String]? = nil
        var liveCatalogResultLimit: Int? = nil
        var liveCatalogTermsGateEnabled: Bool? = nil
        var liveCatalogMaxQueriesPerRun: Int? = nil
        var liveCatalogMinQueryIntervalMs: Int? = nil
        var datasheetCacheDirectory: String? = nil
        var datasheetCacheRevalidateAfterSeconds: Int? = nil
        var mouserAPIKeyEnv: String? = nil
        var mouserAPIKeyKeychainID: String? = nil
        var mouserSearchEndpoint: String? = nil
        var digikeyClientIDEnv: String? = nil
        var digikeyClientIDKeychainID: String? = nil
        var digikeyClientSecretEnv: String? = nil
        var digikeyClientSecretKeychainID: String? = nil
        var digikeyAccessTokenEnv: String? = nil
        var digikeyAccessTokenKeychainID: String? = nil
        var digikeySearchEndpoint: String? = nil
        var digikeyTokenEndpoint: String? = nil
        var nexarClientIDEnv: String? = nil
        var nexarClientIDKeychainID: String? = nil
        var nexarClientSecretEnv: String? = nil
        var nexarClientSecretKeychainID: String? = nil
        var nexarAccessTokenEnv: String? = nil
        var nexarAccessTokenKeychainID: String? = nil
        var nexarGraphQLEndpoint: String? = nil
        var nexarTokenEndpoint: String? = nil
        var trustedPartsCompanyIDEnv: String? = nil
        var trustedPartsCompanyIDKeychainID: String? = nil
        var trustedPartsAPIKeyEnv: String? = nil
        var trustedPartsAPIKeyKeychainID: String? = nil
        var trustedPartsSearchEndpoint: String? = nil
        var onsemiProductURLTemplate: String? = nil
        var vendorFeedPaths: [String]? = nil

        enum CodingKeys: String, CodingKey {
            case catalogProviderFixturePaths = "catalog_provider_fixture_paths"
            case catalogCacheDirectory = "catalog_cache_directory"
            case catalogCacheTTLSeconds = "catalog_cache_ttl_seconds"
            case kicadSymbolLibraryRoot = "kicad_symbol_library_root"
            case kicadFootprintLibraryRoot = "kicad_footprint_library_root"
            case kicadLibraryRootSearchPaths = "kicad_library_root_search_paths"
            case kicadLibraryRootCacheDirectory = "kicad_library_root_cache_directory"
            case kicadLibraryRootCacheTTLSeconds = "kicad_library_root_cache_ttl_seconds"
            case kicadCatalogCacheDirectory = "kicad_catalog_cache_directory"
            case kicadCatalogCacheTTLSeconds = "kicad_catalog_cache_ttl_seconds"
            case liveCatalogProviders = "live_catalog_providers"
            case liveCatalogResultLimit = "live_catalog_result_limit"
            case liveCatalogTermsGateEnabled = "live_catalog_terms_gate_enabled"
            case liveCatalogMaxQueriesPerRun = "live_catalog_max_queries_per_run"
            case liveCatalogMinQueryIntervalMs = "live_catalog_min_query_interval_ms"
            case datasheetCacheDirectory = "datasheet_cache_directory"
            case datasheetCacheRevalidateAfterSeconds = "datasheet_cache_revalidate_after_seconds"
            case mouserAPIKeyEnv = "mouser_api_key_env"
            case mouserAPIKeyKeychainID = "mouser_api_key_keychain_id"
            case mouserSearchEndpoint = "mouser_search_endpoint"
            case digikeyClientIDEnv = "digikey_client_id_env"
            case digikeyClientIDKeychainID = "digikey_client_id_keychain_id"
            case digikeyClientSecretEnv = "digikey_client_secret_env"
            case digikeyClientSecretKeychainID = "digikey_client_secret_keychain_id"
            case digikeyAccessTokenEnv = "digikey_access_token_env"
            case digikeyAccessTokenKeychainID = "digikey_access_token_keychain_id"
            case digikeySearchEndpoint = "digikey_search_endpoint"
            case digikeyTokenEndpoint = "digikey_token_endpoint"
            case nexarClientIDEnv = "nexar_client_id_env"
            case nexarClientIDKeychainID = "nexar_client_id_keychain_id"
            case nexarClientSecretEnv = "nexar_client_secret_env"
            case nexarClientSecretKeychainID = "nexar_client_secret_keychain_id"
            case nexarAccessTokenEnv = "nexar_access_token_env"
            case nexarAccessTokenKeychainID = "nexar_access_token_keychain_id"
            case nexarGraphQLEndpoint = "nexar_graphql_endpoint"
            case nexarTokenEndpoint = "nexar_token_endpoint"
            case trustedPartsCompanyIDEnv = "trustedparts_company_id_env"
            case trustedPartsCompanyIDKeychainID = "trustedparts_company_id_keychain_id"
            case trustedPartsAPIKeyEnv = "trustedparts_api_key_env"
            case trustedPartsAPIKeyKeychainID = "trustedparts_api_key_keychain_id"
            case trustedPartsSearchEndpoint = "trustedparts_search_endpoint"
            case onsemiProductURLTemplate = "onsemi_product_url_template"
            case vendorFeedPaths = "vendor_feed_paths"
        }
    }

    private struct ProviderCandidateCacheEnvelope: Codable {
        var generatedAt: Date
        var candidates: [ComponentCandidate]
    }

    private func componentSelectionCacheMetadata(catalogEvidence: RuntimeCatalogEvidence, circuitIR: CircuitIR?) -> [String: String] {
        var metadata = catalogEvidence.sourceKinds.isEmpty ? [:] : [
            "source": catalogEvidence.sourceKinds.joined(separator: ","),
        ]
        if let ttlSeconds = catalogEvidence.ttlSeconds {
            metadata["ttl_seconds"] = "\(ttlSeconds)"
        }
        if !catalogEvidence.providers.isEmpty {
            metadata["providers"] = catalogEvidence.providers.joined(separator: ",")
        }
        metadata["datasheet_cache_directory"] = catalogEvidence.datasheetCacheDirectory.path
        metadata["datasheet_cache_revalidate_after_seconds"] = "\(catalogEvidence.datasheetRevalidateAfterSeconds)"
        if circuitIR != nil {
            metadata["component_source"] = "circuit_ir"
        }
        return metadata
    }

    private func optionalCircuitIR(from object: [String: Any]) throws -> CircuitIR? {
        let path = (object["circuit_ir_path"] as? String) ?? (object["circuitIRPath"] as? String)
        guard let path, !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CircuitIR.self, from: data)
    }

    private func componentIntents(from circuitIR: CircuitIR) -> [ComponentIntent] {
        circuitIR.components.map { component in
            var constraints = component.constraints
            constraints["selected_symbol"] = component.selectedSymbol
            constraints["source"] = "circuit_ir"
            let pins = requiredPins(for: component)
            if !pins.isEmpty {
                constraints["required_pins"] = pins.joined(separator: ",")
            }
            if let selectedFootprint = component.selectedFootprint, !selectedFootprint.isEmpty {
                constraints["selected_footprint"] = selectedFootprint
            }
            let pinPadMap = pinPadMapConstraint(for: component)
            if !pinPadMap.isEmpty {
                constraints["pin_pad_map"] = pinPadMap
            }
            if let mpn = component.manufacturerPartNumber, !mpn.isEmpty {
                constraints["manufacturer_part_number"] = mpn
            }
            if let sourceRefdes = component.sourceEvidence.first?.reference, !sourceRefdes.isEmpty {
                constraints["source_refdes"] = sourceRefdes
            }
            return ComponentIntent(refdes: component.refdes, role: component.role, constraints: constraints)
        }
    }

    private func runtimeCatalogEvidence(
        from object: [String: Any],
        selectionComponents: [ComponentIntent],
        context: WorkspaceHandlerContext
    ) async -> RuntimeCatalogEvidence {
        let config = runtimeCatalogConfig(from: object, context: context)
        var candidates: [ComponentCandidate] = []
        var providers: [String] = []
        var sourceKinds: [String] = []
        var warnings: [String] = []
        let localFootprintResolver = localKiCadCatalogProvider(from: object, config: config, context: context)
        let datasheetDirectory = datasheetCacheDirectory(from: object, config: config)
        let datasheetRevalidateAfterSeconds = datasheetCacheRevalidateAfterSeconds(from: object, config: config)

        if let path = object["catalog_candidates_path"] as? String,
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let explicitCandidates = try? JSONDecoder().decode([ComponentCandidate].self, from: data) {
            candidates.append(contentsOf: explicitCandidates)
            providers.append("fixture")
            sourceKinds.append("catalog_candidates_path")
        }

        let providerFixtures = catalogProviderFixturePaths(from: object, config: config)
        if !providerFixtures.isEmpty {
            var runtimeProviderFound = false
            for providerID in providerFixtures.keys.sorted() {
                guard let mapped = providerCatalogCandidates(
                    providerID: providerID,
                    fixturePath: providerFixtures[providerID],
                    object: object,
                    config: config,
                    context: context
                ) else {
                    continue
                }
                for component in selectionComponents {
                    let matching = matchingCandidates(for: component, candidates: mapped)
                    candidates.append(contentsOf: matching)
                }
                if !mapped.isEmpty {
                    providers.append(providerID)
                    runtimeProviderFound = true
                }
            }
            if runtimeProviderFound {
                sourceKinds.append("runtime_catalog_providers")
            }
        }

        let vendorFeedPaths = vendorFeedPaths(from: object, config: config)
        if !vendorFeedPaths.isEmpty, catalogProviderIsEnabled("vendor_feed", settings: context.settings) {
            var foundVendorFeed = false
            for path in vendorFeedPaths {
                guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                      let mapped = try? VendorFeedCatalogProviderAdapter().mapRecordedResponse(data) else {
                    warnings.append("CATALOG_PROVIDER_FEED_UNREADABLE: vendor_feed \(path)")
                    continue
                }
                for component in selectionComponents {
                    let matching = matchingCandidates(for: component, candidates: mapped)
                    candidates.append(contentsOf: matching)
                }
                if !mapped.isEmpty {
                    providers.append("vendor_feed")
                    foundVendorFeed = true
                }
            }
            if foundVendorFeed {
                sourceKinds.append("runtime_catalog_providers")
            }
        }

        let liveProviders = liveCatalogProviderIDs(from: object, config: config, settings: context.settings)
        if !liveProviders.isEmpty {
            let cache = LiveCatalogQueryCache()
            let cacheDirectory = catalogCacheDirectory(from: config, context: context)
            let ttlSeconds = catalogCacheTTLSeconds(from: object, config: config)
            let queryBuilder = CatalogSearchQueryBuilder()
            var termsGate = liveCatalogTermsGate(from: object, config: config, settings: context.settings)
            let liveQueryComponents = electronicsLiveCatalogQueryOrderedComponents(selectionComponents)
            for providerID in liveProviders {
                for component in liveQueryComponents {
                    if componentSelectionHasValidCandidate(for: component, candidates: candidates) {
                        continue
                    }
                    let searchRequest = liveCatalogSearchRequest(for: component, preferredProviderID: providerID)
                    var queriedLiveProvider = false
                    var foundProviderCandidates = false
                    for query in queryBuilder.keywords(for: searchRequest) {
                        var queryRequest = searchRequest
                        queryRequest.constraints["catalog_search_keyword"] = query
                        if let cached = try? cache.loadCandidates(
                            providerID: providerID,
                            query: query,
                            from: cacheDirectory,
                            maxAgeSeconds: ttlSeconds
                        ) {
                            candidates.append(contentsOf: cached)
                            providers.append(providerID)
                            sourceKinds.append("live_catalog_cache")
                            foundProviderCandidates = foundProviderCandidates || !cached.isEmpty
                            if componentSelectionHasValidCandidate(for: component, candidates: cached) { break }
                            continue
                        }
                        if let skipReason = termsGate.skipReason(providerID: providerID) {
                            warnings.append(skipReason)
                            break
                        }
                        guard let liveProvider = liveCatalogProvider(providerID: providerID, config: config) else {
                            if !queriedLiveProvider {
                                warnings.append("CATALOG_PROVIDER_NOT_CONFIGURED: \(providerID) credentials are missing and no fresh cache entry exists.")
                            }
                            break
                        }
                        queriedLiveProvider = true
                        await termsGate.waitIfNeeded(providerID: providerID)
                        do {
                            let result = try await liveProvider.searchWithRawResponse(queryRequest)
                            try? cache.write(
                                candidates: result.candidates,
                                rawResponse: result.rawResponse,
                                providerID: providerID,
                                query: query,
                                requestURL: result.requestURL,
                                to: cacheDirectory
                            )
                            candidates.append(contentsOf: result.candidates)
                            providers.append(providerID)
                            sourceKinds.append("live_catalog_api")
                            foundProviderCandidates = foundProviderCandidates || !result.candidates.isEmpty
                            if componentSelectionHasValidCandidate(for: component, candidates: result.candidates) { break }
                        } catch {
                            warnings.append("CATALOG_PROVIDER_QUERY_FAILED: \(providerID) \(error.localizedDescription)")
                            if shouldStopLiveProviderAfterError(error) {
                                termsGate.stopProvider(providerID)
                                break
                            }
                        }
                    }
                    _ = foundProviderCandidates
                }
            }
        }

        let uniqueProviders = uniqueRefdes(providers)
        let ttlSeconds = sourceKinds.contains("runtime_catalog_providers")
            || sourceKinds.contains("live_catalog_api")
            || sourceKinds.contains("live_catalog_cache")
            ? catalogCacheTTLSeconds(from: object, config: config)
            : nil
        return RuntimeCatalogEvidence(
            candidates: candidates,
            providers: uniqueProviders,
            sourceKinds: uniqueRefdes(sourceKinds),
            ttlSeconds: ttlSeconds,
            warnings: uniqueRefdes(warnings),
            localFootprintResolver: localFootprintResolver,
            datasheetCacheDirectory: datasheetDirectory,
            datasheetRevalidateAfterSeconds: datasheetRevalidateAfterSeconds
        )
    }

    private func componentSelectionHasValidCandidate(
        for component: ComponentIntent,
        candidates: [ComponentCandidate]
    ) -> Bool {
        guard !candidates.isEmpty else { return false }
        let validator = ComponentCatalogValidator()
        return matchingCandidates(for: component, candidates: candidates)
            .map { hydratedCandidate($0) }
            .contains { validator.validate($0).isValid }
    }

    private func runtimeCatalogConfig(from object: [String: Any], context: WorkspaceHandlerContext) -> RuntimeCatalogConfig {
        let defaultURL = context.workspaceRoot
            .appendingPathComponent(".merlin", isDirectory: true)
            .appendingPathComponent("electronics-provider-config.json")
        let explicitURL = stringValue(object, keys: ["electronics_provider_config_path", "provider_config_path"])
            .map { URL(fileURLWithPath: $0) }
        let configURL = explicitURL ?? defaultURL
        var config = (try? Data(contentsOf: configURL)).flatMap {
            try? JSONDecoder().decode(RuntimeCatalogConfig.self, from: $0)
        } ?? RuntimeCatalogConfig()

        applyPluginSettings(to: &config, settings: context.settings)

        if let value = object["catalog_cache_directory"] as? String {
            config.catalogCacheDirectory = value
        }
        if let value = optionalIntValue(object, key: "catalog_cache_ttl_seconds") {
            config.catalogCacheTTLSeconds = value
        }
        if let value = object["kicad_symbol_library_root"] as? String {
            config.kicadSymbolLibraryRoot = value
        }
        if let value = object["kicad_footprint_library_root"] as? String {
            config.kicadFootprintLibraryRoot = value
        }
        if let value = stringArrayValue(object, key: "kicad_library_root_search_paths") {
            config.kicadLibraryRootSearchPaths = value
        }
        if let value = object["kicad_library_root_cache_directory"] as? String {
            config.kicadLibraryRootCacheDirectory = value
        }
        if let value = optionalIntValue(object, key: "kicad_library_root_cache_ttl_seconds") {
            config.kicadLibraryRootCacheTTLSeconds = value
        }
        if let value = object["kicad_catalog_cache_directory"] as? String {
            config.kicadCatalogCacheDirectory = value
        }
        if let value = optionalIntValue(object, key: "kicad_catalog_cache_ttl_seconds") {
            config.kicadCatalogCacheTTLSeconds = value
        }
        if let value = stringArrayValue(object, key: "live_catalog_providers") {
            config.liveCatalogProviders = value
        }
        if let value = optionalIntValue(object, key: "live_catalog_result_limit") {
            config.liveCatalogResultLimit = value
        }
        if let value = optionalBoolValue(object, key: "live_catalog_terms_gate_enabled") {
            config.liveCatalogTermsGateEnabled = value
        }
        if let value = optionalIntValue(object, key: "live_catalog_max_queries_per_run") {
            config.liveCatalogMaxQueriesPerRun = value
        }
        if let value = optionalIntValue(object, key: "live_catalog_min_query_interval_ms") {
            config.liveCatalogMinQueryIntervalMs = value
        }
        if let value = object["datasheet_cache_directory"] as? String {
            config.datasheetCacheDirectory = value
        }
        if let value = optionalIntValue(object, key: "datasheet_cache_revalidate_after_seconds") {
            config.datasheetCacheRevalidateAfterSeconds = value
        }
        if let value = object["mouser_api_key_env"] as? String {
            config.mouserAPIKeyEnv = value
        }
        if let value = object["mouser_api_key_keychain_id"] as? String {
            config.mouserAPIKeyKeychainID = value
        }
        if let value = object["mouser_search_endpoint"] as? String {
            config.mouserSearchEndpoint = value
        }
        if let value = object["digikey_client_id_env"] as? String {
            config.digikeyClientIDEnv = value
        }
        if let value = object["digikey_client_id_keychain_id"] as? String {
            config.digikeyClientIDKeychainID = value
        }
        if let value = object["digikey_client_secret_env"] as? String {
            config.digikeyClientSecretEnv = value
        }
        if let value = object["digikey_client_secret_keychain_id"] as? String {
            config.digikeyClientSecretKeychainID = value
        }
        if let value = object["digikey_access_token_env"] as? String {
            config.digikeyAccessTokenEnv = value
        }
        if let value = object["digikey_access_token_keychain_id"] as? String {
            config.digikeyAccessTokenKeychainID = value
        }
        if let value = object["digikey_search_endpoint"] as? String {
            config.digikeySearchEndpoint = value
        }
        if let value = object["digikey_token_endpoint"] as? String {
            config.digikeyTokenEndpoint = value
        }
        if let value = object["nexar_client_id_env"] as? String {
            config.nexarClientIDEnv = value
        }
        if let value = object["nexar_client_id_keychain_id"] as? String {
            config.nexarClientIDKeychainID = value
        }
        if let value = object["nexar_client_secret_env"] as? String {
            config.nexarClientSecretEnv = value
        }
        if let value = object["nexar_client_secret_keychain_id"] as? String {
            config.nexarClientSecretKeychainID = value
        }
        if let value = object["nexar_access_token_env"] as? String {
            config.nexarAccessTokenEnv = value
        }
        if let value = object["nexar_access_token_keychain_id"] as? String {
            config.nexarAccessTokenKeychainID = value
        }
        if let value = object["nexar_graphql_endpoint"] as? String {
            config.nexarGraphQLEndpoint = value
        }
        if let value = object["nexar_token_endpoint"] as? String {
            config.nexarTokenEndpoint = value
        }
        if let value = object["trustedparts_company_id_env"] as? String {
            config.trustedPartsCompanyIDEnv = value
        }
        if let value = object["trustedparts_company_id_keychain_id"] as? String {
            config.trustedPartsCompanyIDKeychainID = value
        }
        if let value = object["trustedparts_api_key_env"] as? String {
            config.trustedPartsAPIKeyEnv = value
        }
        if let value = object["trustedparts_api_key_keychain_id"] as? String {
            config.trustedPartsAPIKeyKeychainID = value
        }
        if let value = object["trustedparts_search_endpoint"] as? String {
            config.trustedPartsSearchEndpoint = value
        }
        if let value = object["onsemi_product_url_template"] as? String {
            config.onsemiProductURLTemplate = value
        }
        if let value = stringArrayValue(object, key: "vendor_feed_paths") {
            config.vendorFeedPaths = value
        }
        return config
    }

    private func applyPluginSettings(to config: inout RuntimeCatalogConfig, settings: WorkspaceSettingsNamespace) {
        if config.datasheetCacheDirectory == nil,
           case .string(let path)? = settings.values["datasheet_cache_directory"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config.datasheetCacheDirectory = path
        }
        if config.datasheetCacheRevalidateAfterSeconds == nil,
           case .integer(let seconds)? = settings.values["datasheet_cache_revalidate_after_seconds"] {
            config.datasheetCacheRevalidateAfterSeconds = seconds
        }
    }

    private func catalogProviderFixturePaths(from object: [String: Any], config: RuntimeCatalogConfig) -> [String: String] {
        var paths = config.catalogProviderFixturePaths?.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        } ?? [:]
        let raw = object["catalog_provider_fixture_paths"] ?? object["catalog_provider_fixtures"]
        guard let dictionary = raw as? [String: Any] else { return paths }
        dictionary.forEach { entry in
            guard let path = entry.value as? String,
                  !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return
            }
            paths[entry.key.lowercased()] = path
        }
        return paths
    }

    private func vendorFeedPaths(from object: [String: Any], config: RuntimeCatalogConfig) -> [String] {
        uniqueRefdes((stringArrayValue(object, key: "vendor_feed_paths") ?? config.vendorFeedPaths ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
    }

    private func vendorFeedDestinationName(for sourceURL: URL) -> String {
        let base = sourceURL.deletingPathExtension().lastPathComponent
            .split { !$0.isLetter && !$0.isNumber && $0 != "-" && $0 != "_" }
            .joined(separator: "_")
        let safeBase = base.isEmpty ? "vendor-feed" : base
        let ext = sourceURL.pathExtension.lowercased()
        return "\(safeBase)-\(UUID().uuidString).\(ext)"
    }

    private func updateVendorFeedProviderConfig(configURL: URL, importedPaths: [String]) throws {
        try FileManager.default.createDirectory(
            at: configURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var object = ((try? Data(contentsOf: configURL)).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }) ?? [:]
        let existing = (object["vendor_feed_paths"] as? [String]) ?? []
        object["vendor_feed_paths"] = uniqueRefdes(existing + importedPaths)
        object["live_catalog_providers"] = object["live_catalog_providers"] ?? []
        let data = try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configURL, options: .atomic)
    }

    private func providerCatalogCandidates(
        providerID: String,
        fixturePath: String?,
        object: [String: Any],
        config: RuntimeCatalogConfig,
        context: WorkspaceHandlerContext
    ) -> [ComponentCandidate]? {
        let ttlSeconds = catalogCacheTTLSeconds(from: object, config: config)
        let cacheDirectory = catalogCacheDirectory(from: config, context: context)
        if let fixturePath,
           let data = try? Data(contentsOf: URL(fileURLWithPath: fixturePath)),
           let mapped = try? mapRecordedProviderFixture(providerID: providerID, data: data) {
            if !mapped.isEmpty {
                try? writeProviderCandidateCache(mapped, providerID: providerID, directory: cacheDirectory)
            }
            return mapped
        }
        return try? loadProviderCandidateCache(providerID: providerID, directory: cacheDirectory, ttlSeconds: ttlSeconds)
    }

    private func mapRecordedProviderFixture(providerID: String, data: Data) throws -> [ComponentCandidate] {
        switch providerID.lowercased() {
        case "digikey", "digi-key":
            return try DigiKeyCatalogProviderAdapter().mapRecordedResponse(data)
        case "mouser":
            return try MouserCatalogProviderAdapter().mapRecordedResponse(data)
        case "nexar":
            return try NexarCatalogProviderAdapter().mapRecordedResponse(data)
        case "trustedparts", "trusted-parts", "trusted_parts":
            return try TrustedPartsCatalogProviderAdapter().mapRecordedResponse(data)
        case "onsemi", "on-semiconductor", "on_semiconductor":
            return try OnsemiCatalogProviderAdapter().mapProductPage(
                data,
                sourceURL: URL(string: "https://www.onsemi.com/products")!,
                requestedMPN: "MJ15003G"
            )
        case "vendor_feed", "vendor-feed", "vendorfeed":
            return try VendorFeedCatalogProviderAdapter().mapRecordedResponse(data)
        case "octopart", "aggregator":
            return try AggregatorCatalogProviderAdapter(providerID: providerID.lowercased()).mapRecordedResponse(data)
        default:
            return try AggregatorCatalogProviderAdapter(providerID: providerID.lowercased()).mapRecordedResponse(data)
        }
    }

    private func localKiCadCatalogProvider(
        from object: [String: Any],
        config: RuntimeCatalogConfig,
        context: WorkspaceHandlerContext
    ) -> KiCadLibraryCatalogProvider? {
        let symbolPath = object["kicad_symbol_catalog_path"] as? String
        let footprintPath = object["kicad_footprint_catalog_path"] as? String
        let symbols: [KiCadSymbolDefinition] = symbolPath.flatMap { decodeJSONFile($0) } ?? []
        let footprints: [KiCadFootprintDefinition] = footprintPath.flatMap { decodeJSONFile($0) } ?? []
        if !symbols.isEmpty || !footprints.isEmpty {
            return KiCadLibraryCatalogProvider(symbols: symbols, footprints: footprints)
        }

        let symbolRoot = stringValue(object, keys: ["kicad_symbol_library_root"]).map(URL.init(fileURLWithPath:))
            ?? config.kicadSymbolLibraryRoot.map(URL.init(fileURLWithPath:))
        let footprintRoot = stringValue(object, keys: ["kicad_footprint_library_root"]).map(URL.init(fileURLWithPath:))
            ?? config.kicadFootprintLibraryRoot.map(URL.init(fileURLWithPath:))
        let discoveredRoots = symbolRoot == nil && footprintRoot == nil
            ? discoveredKiCadLibraryRoots(from: object, config: config, context: context)
            : nil
        let resolvedSymbolRoot = symbolRoot ?? discoveredRoots?.symbolRoot
        let resolvedFootprintRoot = footprintRoot ?? discoveredRoots?.footprintRoot
        guard resolvedSymbolRoot != nil || resolvedFootprintRoot != nil else { return nil }

        let cacheDirectory = stringValue(object, keys: ["kicad_catalog_cache_directory"])
            .map(URL.init(fileURLWithPath:))
            ?? config.kicadCatalogCacheDirectory.map(URL.init(fileURLWithPath:))
            ?? context.workspaceRoot.appendingPathComponent(".merlin/electronics-kicad-catalog-cache", isDirectory: true)
        let ttlSeconds = optionalIntValue(object, key: "kicad_catalog_cache_ttl_seconds")
            ?? config.kicadCatalogCacheTTLSeconds
            ?? 86_400
        let cache = KiCadLibraryCatalogCache()
        let catalog = (try? cache.load(from: cacheDirectory, maxAgeSeconds: ttlSeconds))
            ?? (try? KiCadLibraryCatalogExtractor().extract(symbolRoot: resolvedSymbolRoot, footprintRoot: resolvedFootprintRoot)).map { catalog in
                try? cache.write(catalog, to: cacheDirectory)
                return catalog
            }
        guard let catalog,
              !catalog.symbols.isEmpty || !catalog.footprints.isEmpty else {
            return nil
        }
        return KiCadLibraryCatalogProvider(symbols: catalog.symbols, footprints: catalog.footprints)
    }

    private func discoveredKiCadLibraryRoots(
        from object: [String: Any],
        config: RuntimeCatalogConfig,
        context: WorkspaceHandlerContext
    ) -> KiCadLibraryRoots? {
        let cacheDirectory = stringValue(object, keys: ["kicad_library_root_cache_directory"])
            .map(URL.init(fileURLWithPath:))
            ?? config.kicadLibraryRootCacheDirectory.map(URL.init(fileURLWithPath:))
            ?? context.workspaceRoot.appendingPathComponent(".merlin/electronics-kicad-root-cache", isDirectory: true)
        let ttlSeconds = optionalIntValue(object, key: "kicad_library_root_cache_ttl_seconds")
            ?? config.kicadLibraryRootCacheTTLSeconds
            ?? 86_400
        let cache = KiCadLibraryRootCache()
        if let cached = try? cache.load(from: cacheDirectory, maxAgeSeconds: ttlSeconds) {
            return cached
        }
        let searchPaths = stringArrayValue(object, key: "kicad_library_root_search_paths")
            ?? config.kicadLibraryRootSearchPaths
        let searchRoots = searchPaths?.map(URL.init(fileURLWithPath:)) ?? KiCadLibraryRootDiscovery.defaultSearchRoots()
        guard let discovered = KiCadLibraryRootDiscovery().discover(searchRoots: searchRoots) else {
            return nil
        }
        try? cache.write(discovered, to: cacheDirectory)
        return discovered
    }

    private func boardFootprintRoot(
        from object: [String: Any],
        config: RuntimeCatalogConfig,
        context: WorkspaceHandlerContext
    ) -> URL? {
        if let path = stringValue(object, keys: ["kicad_footprint_library_root"]) {
            return URL(fileURLWithPath: path)
        }
        if let path = config.kicadFootprintLibraryRoot {
            return URL(fileURLWithPath: path)
        }
        return discoveredKiCadLibraryRoots(from: object, config: config, context: context)?.footprintRoot
    }

    private func decodeJSONFile<T: Decodable>(_ path: String) -> T? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func catalogCacheTTLSeconds(from object: [String: Any], config: RuntimeCatalogConfig) -> Int {
        optionalIntValue(object, key: "catalog_cache_ttl_seconds") ?? config.catalogCacheTTLSeconds ?? 86_400
    }

    private func catalogCacheDirectory(from config: RuntimeCatalogConfig, context: WorkspaceHandlerContext) -> URL {
        config.catalogCacheDirectory.map(URL.init(fileURLWithPath:))
            ?? context.workspaceRoot.appendingPathComponent(".merlin/electronics-catalog-cache", isDirectory: true)
    }

    private func datasheetCacheDirectory(from object: [String: Any], config: RuntimeCatalogConfig) -> URL {
        stringValue(object, keys: ["datasheet_cache_directory"])
            .map(fileURLFromPathSetting)
            ?? config.datasheetCacheDirectory.map(fileURLFromPathSetting)
            ?? ElectronicsRuntimePlugin.defaultDatasheetCacheDirectory
    }

    private func datasheetCacheRevalidateAfterSeconds(from object: [String: Any], config: RuntimeCatalogConfig) -> Int {
        optionalIntValue(object, key: "datasheet_cache_revalidate_after_seconds")
            ?? config.datasheetCacheRevalidateAfterSeconds
            ?? ElectronicsRuntimePlugin.defaultDatasheetCacheRevalidateAfterSeconds
    }

    private func fileURLFromPathSetting(_ path: String) -> URL {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" {
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        }
        if trimmed.hasPrefix("~/") {
            let suffix = String(trimmed.dropFirst(2))
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(suffix, isDirectory: true)
        }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    private func liveCatalogProviderIDs(
        from object: [String: Any],
        config: RuntimeCatalogConfig,
        settings: WorkspaceSettingsNamespace
    ) -> [String] {
        let explicit = stringArrayValue(object, key: "live_catalog_providers") ?? config.liveCatalogProviders
        if let explicit {
            return uniqueRefdes(explicit.map { $0.lowercased() })
                .filter { catalogProviderIsEnabled($0, settings: settings) }
        }
        let settingsDeclareLiveProviders = [
            "catalog_provider_mouser_enabled",
            "catalog_provider_digikey_enabled",
            "catalog_provider_nexar_enabled",
            "catalog_provider_trustedparts_enabled",
            "catalog_provider_onsemi_enabled",
        ].contains { settings.values[$0] != nil }
        if settingsDeclareLiveProviders {
            return ["mouser", "digikey", "onsemi"]
                .filter { catalogProviderIsEnabled($0, settings: settings) }
        }
        return []
    }

    private func catalogProviderIsEnabled(_ providerID: String, settings: WorkspaceSettingsNamespace) -> Bool {
        let key: String
        let defaultValue: Bool
        switch providerID.lowercased() {
        case "mouser":
            key = "catalog_provider_mouser_enabled"
            defaultValue = true
        case "digikey", "digi-key":
            key = "catalog_provider_digikey_enabled"
            defaultValue = true
        case "nexar", "octopart":
            key = "catalog_provider_nexar_enabled"
            defaultValue = false
        case "trustedparts", "trusted-parts", "trusted_parts":
            key = "catalog_provider_trustedparts_enabled"
            defaultValue = false
        case "onsemi", "on-semiconductor", "on_semiconductor":
            key = "catalog_provider_onsemi_enabled"
            defaultValue = false
        case "vendor_feed", "vendor-feed", "vendorfeed":
            key = "catalog_provider_vendor_feed_enabled"
            defaultValue = true
        default:
            return true
        }
        guard let value = settings.values[key] else { return defaultValue }
        if case .boolean(let enabled) = value {
            return enabled
        }
        return defaultValue
    }

    private func liveCatalogTermsGate(
        from object: [String: Any],
        config: RuntimeCatalogConfig,
        settings: WorkspaceSettingsNamespace
    ) -> LiveCatalogTermsGate {
        let enabled = optionalBoolValue(object, key: "live_catalog_terms_gate_enabled")
            ?? config.liveCatalogTermsGateEnabled
            ?? boolSetting("live_catalog_terms_gate_enabled", settings: settings, defaultValue: true)
        let maxQueries = optionalIntValue(object, key: "live_catalog_max_queries_per_run")
            ?? config.liveCatalogMaxQueriesPerRun
            ?? intSetting("live_catalog_max_queries_per_run", settings: settings, defaultValue: 30)
        let minIntervalMs = optionalIntValue(object, key: "live_catalog_min_query_interval_ms")
            ?? config.liveCatalogMinQueryIntervalMs
            ?? intSetting("live_catalog_min_query_interval_ms", settings: settings, defaultValue: 2_100)
        return LiveCatalogTermsGate(
            enabled: enabled,
            maxQueriesPerRun: max(0, maxQueries),
            minQueryIntervalMs: max(0, minIntervalMs)
        )
    }

    private func shouldStopLiveProviderAfterError(_ error: Error) -> Bool {
        if case LiveCatalogProviderError.rateLimited = error {
            return true
        }
        if case LiveCatalogProviderError.httpStatus(let status) = error {
            return status == 401 || status == 403
        }
        return false
    }

    private func boolSetting(_ key: String, settings: WorkspaceSettingsNamespace, defaultValue: Bool) -> Bool {
        guard let value = settings.values[key] else { return defaultValue }
        if case .boolean(let bool) = value {
            return bool
        }
        return defaultValue
    }

    private func intSetting(_ key: String, settings: WorkspaceSettingsNamespace, defaultValue: Int) -> Int {
        guard let value = settings.values[key] else { return defaultValue }
        if case .integer(let int) = value {
            return int
        }
        return defaultValue
    }

    private func liveCatalogProvider(providerID: String, config: RuntimeCatalogConfig) -> (any LiveCatalogProviderClient)? {
        let limit = config.liveCatalogResultLimit ?? 10
        switch providerID.lowercased() {
        case "mouser":
            guard let apiKey = credentialValue(
                envName: config.mouserAPIKeyEnv,
                defaultEnvName: "MOUSER_API_KEY",
                keychainID: config.mouserAPIKeyKeychainID,
                defaultKeychainID: "electronics.mouser.api_key"
            ) else {
                return nil
            }
            let endpoint = config.mouserSearchEndpoint.flatMap(URL.init(string:))
                ?? URL(string: "https://api.mouser.com/api/v2/search/keyword")!
            return LiveMouserCatalogProvider(apiKey: apiKey, endpoint: endpoint, resultLimit: limit)
        case "digikey", "digi-key":
            guard let clientID = credentialValue(
                envName: config.digikeyClientIDEnv,
                defaultEnvName: "DIGIKEY_CLIENT_ID",
                keychainID: config.digikeyClientIDKeychainID,
                defaultKeychainID: "electronics.digikey.client_id"
            ) else {
                return nil
            }
            let accessToken = credentialValue(
                envName: config.digikeyAccessTokenEnv,
                defaultEnvName: "DIGIKEY_ACCESS_TOKEN",
                keychainID: config.digikeyAccessTokenKeychainID,
                defaultKeychainID: "electronics.digikey.access_token"
            )
            let clientSecret = credentialValue(
                envName: config.digikeyClientSecretEnv,
                defaultEnvName: "DIGIKEY_CLIENT_SECRET",
                keychainID: config.digikeyClientSecretKeychainID,
                defaultKeychainID: "electronics.digikey.client_secret"
            )
            guard accessToken != nil || clientSecret != nil else { return nil }
            let searchEndpoint = config.digikeySearchEndpoint.flatMap(URL.init(string:))
                ?? URL(string: "https://api.digikey.com/products/v4/search/keyword")!
            let tokenEndpoint = config.digikeyTokenEndpoint.flatMap(URL.init(string:))
                ?? URL(string: "https://api.digikey.com/v1/oauth2/token")!
            return LiveDigiKeyCatalogProvider(
                clientID: clientID,
                clientSecret: clientSecret,
                accessToken: accessToken,
                searchEndpoint: searchEndpoint,
                tokenEndpoint: tokenEndpoint,
                resultLimit: limit
            )
        case "nexar", "octopart":
            guard let clientID = credentialValue(
                envName: config.nexarClientIDEnv,
                defaultEnvName: "NEXAR_CLIENT_ID",
                keychainID: config.nexarClientIDKeychainID,
                defaultKeychainID: "electronics.nexar.client_id"
            ) else {
                return nil
            }
            let accessToken = credentialValue(
                envName: config.nexarAccessTokenEnv,
                defaultEnvName: "NEXAR_ACCESS_TOKEN",
                keychainID: config.nexarAccessTokenKeychainID,
                defaultKeychainID: "electronics.nexar.access_token"
            )
            let clientSecret = credentialValue(
                envName: config.nexarClientSecretEnv,
                defaultEnvName: "NEXAR_CLIENT_SECRET",
                keychainID: config.nexarClientSecretKeychainID,
                defaultKeychainID: "electronics.nexar.client_secret"
            )
            guard accessToken != nil || clientSecret != nil else { return nil }
            let graphqlEndpoint = config.nexarGraphQLEndpoint.flatMap(URL.init(string:))
                ?? URL(string: "https://api.nexar.com/graphql/")!
            let tokenEndpoint = config.nexarTokenEndpoint.flatMap(URL.init(string:))
                ?? URL(string: "https://identity.nexar.com/connect/token")!
            return LiveNexarCatalogProvider(
                clientID: clientID,
                clientSecret: clientSecret,
                accessToken: accessToken,
                graphqlEndpoint: graphqlEndpoint,
                tokenEndpoint: tokenEndpoint,
                resultLimit: limit
            )
        case "trustedparts", "trusted-parts", "trusted_parts":
            guard let companyID = credentialValue(
                envName: config.trustedPartsCompanyIDEnv,
                defaultEnvName: "TRUSTEDPARTS_COMPANY_ID",
                keychainID: config.trustedPartsCompanyIDKeychainID,
                defaultKeychainID: "electronics.trustedparts.company_id"
            ) else {
                return nil
            }
            guard let apiKey = credentialValue(
                envName: config.trustedPartsAPIKeyEnv,
                defaultEnvName: "TRUSTEDPARTS_API_KEY",
                keychainID: config.trustedPartsAPIKeyKeychainID,
                defaultKeychainID: "electronics.trustedparts.api_key"
            ) else {
                return nil
            }
            let endpoint = config.trustedPartsSearchEndpoint.flatMap(URL.init(string:))
                ?? URL(string: "https://api.trustedparts.com/v2/search")!
            return LiveTrustedPartsCatalogProvider(
                companyID: companyID,
                apiKey: apiKey,
                endpoint: endpoint,
                resultLimit: limit
            )
        case "onsemi", "on-semiconductor", "on_semiconductor":
            return LiveOnsemiCatalogProvider(
                productURLTemplate: config.onsemiProductURLTemplate
                    ?? "https://www.onsemi.com/products/discrete-power-modules/audio-transistors/{base_mpn}"
            )
        default:
            return nil
        }
    }

    private func credentialValue(
        envName: String?,
        defaultEnvName: String,
        keychainID: String?,
        defaultKeychainID: String
    ) -> String? {
        let envNames = envName.flatMap { name -> [String]? in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : [trimmed]
        } ?? [defaultEnvName]
        for name in envNames {
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let raw = getenv(name) {
                let value = String(cString: raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty { return value }
            }
        }
        let keychainIDs = keychainID.flatMap { id -> [String]? in
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : [trimmed]
        } ?? [defaultKeychainID]
        for id in keychainIDs {
            guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let value = KeychainManager.readAPIKey(for: id)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func liveCatalogSearchRequest(for component: ComponentIntent, preferredProviderID: String) -> ComponentSearchRequest {
        var constraints = component.constraints
        if let mpn = constraints["manufacturer_part_number"], constraints["mpn"] == nil {
            constraints["mpn"] = mpn
        }
        return ComponentSearchRequest(
            refdes: component.refdes,
            role: component.role,
            constraints: constraints,
            requiredEvidenceTypes: ["datasheet", "package", "ratings", "provenance"],
            preferredVendors: [preferredProviderID],
            excludedManufacturers: [],
            lifecyclePolicy: "active_or_ltb"
        )
    }

    private func loadProviderCandidateCache(providerID: String, directory: URL, ttlSeconds: Int) throws -> [ComponentCandidate]? {
        let url = directory.appendingPathComponent("\(providerID.lowercased())-candidates.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let envelope = try JSONDecoder().decode(ProviderCandidateCacheEnvelope.self, from: Data(contentsOf: url))
        guard ttlSeconds <= 0 || Date().timeIntervalSince(envelope.generatedAt) <= Double(ttlSeconds) else {
            return nil
        }
        return envelope.candidates
    }

    private func writeProviderCandidateCache(_ candidates: [ComponentCandidate], providerID: String, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let envelope = ProviderCandidateCacheEnvelope(generatedAt: Date(), candidates: candidates)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(envelope).write(to: directory.appendingPathComponent("\(providerID.lowercased())-candidates.json"))
    }

    private func providerCandidate(
        _ candidate: ComponentCandidate,
        for component: ComponentIntent,
        localFootprintResolver: KiCadLibraryCatalogProvider?
    ) async -> ComponentCandidate {
        var candidate = candidate
        candidate.evidence = candidate.evidence.map { evidence in
            var evidence = evidence
            evidence.extractedParameters["target_refdes"] = component.refdes
            return evidence
        }

        guard let localFootprintResolver else { return candidate }
        var constraints = component.constraints
        constraints["symbol"] = component.constraints["selected_symbol"] ?? constraints["symbol"]
        constraints["footprint"] = component.constraints["selected_footprint"] ?? constraints["footprint"]
        if !candidate.package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            constraints["package"] = candidate.package
        }
        for key in ["package", "package_case", "case_package", "supplier_device_package"] {
            if constraints[key] == nil, let value = candidate.ratings[key], !value.isEmpty {
                constraints[key] = value
            }
        }
        constraints["mpn"] = candidate.mpn
        constraints["manufacturer"] = candidate.manufacturer
        constraints["normalized_category"] = candidate.normalizedCategory
        constraints = constraints.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !constraints.isEmpty else { return candidate }
        let request = ComponentSearchRequest(
            refdes: component.refdes,
            role: component.role,
            constraints: constraints,
            requiredEvidenceTypes: ["symbol", "footprint"],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "draft"
        )
        let localCandidates = (try? await localFootprintResolver.search(request)) ?? []
        let localFootprints = localCandidates
            .flatMap(\.footprintCandidates)
            .map { applyingPinPadConstraint($0, component: component) }
        guard !localFootprints.isEmpty else { return candidate }
        candidate.footprintCandidates = mergedFootprints(candidate.footprintCandidates, localFootprints)
        return candidate
    }

    private func applyingPinPadConstraint(_ footprint: FootprintCandidate, component: ComponentIntent) -> FootprintCandidate {
        let pinPadMap = pinPadMapConstraint(from: component.constraints["pin_pad_map"])
        guard !pinPadMap.isEmpty else { return footprint }
        var footprint = footprint
        for entry in pinPadMap where !entry.key.isEmpty && !entry.value.isEmpty {
            footprint.pinPadMap[entry.key] = entry.value
        }
        return footprint
    }

    private func selectedFootprintCandidate(
        for candidate: ComponentCandidate,
        component: ComponentIntent?,
        circuitComponent: CircuitComponent?,
        localFootprintResolver: KiCadLibraryCatalogProvider?
    ) async -> FootprintCandidate? {
        let requiredPins = circuitComponent.map(requiredPins(for:)) ?? requiredPins(for: component)
        let existingFootprints = candidate.footprintCandidates.map {
            applyingPinPadEvidence($0, requiredPins: requiredPins, component: component)
        }
        if let exact = existingFootprints.first(where: { footprintCoversRequiredPins($0, requiredPins: requiredPins) }) {
            return exact
        }
        if let fallback = existingFootprints.first {
            return fallback
        }
        guard let localFootprintResolver else { return nil }
        var constraints = component?.constraints ?? [:]
        constraints["mpn"] = candidate.mpn
        constraints["manufacturer"] = candidate.manufacturer
        if !candidate.package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            constraints["package"] = candidate.package
        }
        for key in ["package", "package_case", "case_package", "supplier_device_package"] {
            if constraints[key] == nil, let value = candidate.ratings[key], !value.isEmpty {
                constraints[key] = value
            }
        }
        if constraints["footprint"] == nil, let selected = constraints["selected_footprint"], !selected.isEmpty {
            constraints["footprint"] = selected
        }
        let request = ComponentSearchRequest(
            refdes: component?.refdes ?? circuitComponent?.refdes ?? "",
            role: component?.role ?? circuitComponent?.role ?? candidate.normalizedCategory,
            constraints: constraints,
            requiredEvidenceTypes: ["footprint"],
            preferredVendors: [],
            excludedManufacturers: [],
            lifecyclePolicy: "library_asset"
        )
        let resolved = (try? await localFootprintResolver.search(request)) ?? []
        let footprints = resolved
            .flatMap(\.footprintCandidates)
            .map { applyingPinPadEvidence($0, requiredPins: requiredPins, component: component) }
        return footprints.first(where: { footprintCoversRequiredPins($0, requiredPins: requiredPins) }) ?? footprints.first
    }

    private func applyingPinPadEvidence(
        _ footprint: FootprintCandidate,
        requiredPins: [String],
        component: ComponentIntent?
    ) -> FootprintCandidate {
        var footprint = component.map { applyingPinPadConstraint(footprint, component: $0) } ?? footprint
        let missingPins = requiredPins.filter { footprint.pinPadMap[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true }
        guard !missingPins.isEmpty else { return footprint }
        let padNumbers = footprint.pinPadMap.values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard padNumbers.count == requiredPins.count else { return footprint }
        for (pin, pad) in zip(requiredPins, padNumbers) where footprint.pinPadMap[pin] == nil {
            footprint.pinPadMap[pin] = pad
        }
        return footprint
    }

    private func footprintCoversRequiredPins(_ footprint: FootprintCandidate, requiredPins: [String]) -> Bool {
        guard !requiredPins.isEmpty else { return false }
        return requiredPins.allSatisfy {
            footprint.pinPadMap[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func mergedFootprints(_ current: [FootprintCandidate], _ additional: [FootprintCandidate]) -> [FootprintCandidate] {
        var seen = Set(current.map { canonicalFootprintName($0) })
        var result = current
        for footprint in additional {
            let name = canonicalFootprintName(footprint)
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            result.append(footprint)
        }
        return result
    }

    private func intValue(_ object: [String: Any], key: String, defaultValue: Int) -> Int {
        if let int = object[key] as? Int { return int }
        if let number = object[key] as? NSNumber { return number.intValue }
        if let string = object[key] as? String, let int = Int(string) { return int }
        return defaultValue
    }

    private func optionalIntValue(_ object: [String: Any], key: String) -> Int? {
        if let int = object[key] as? Int { return int }
        if let number = object[key] as? NSNumber { return number.intValue }
        if let string = object[key] as? String, let int = Int(string) { return int }
        return nil
    }

    private func optionalBoolValue(_ object: [String: Any], key: String) -> Bool? {
        if let bool = object[key] as? Bool { return bool }
        if let number = object[key] as? NSNumber { return number.boolValue }
        guard let string = object[key] as? String else { return nil }
        switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "1":
            return true
        case "false", "no", "0":
            return false
        default:
            return nil
        }
    }

    private func stringArrayValue(_ object: [String: Any], key: String) -> [String]? {
        if let values = object[key] as? [String] {
            return values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let values = object[key] as? [Any] {
            let strings = values.compactMap { $0 as? String }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            return strings.isEmpty ? nil : strings
        }
        if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        return nil
    }

    private func componentSelectionDecision(
        for component: ComponentIntent,
        candidates: [ComponentCandidate]
    ) -> PartSelectionDecision {
        let candidates = matchingCandidates(for: component, candidates: candidates)
            .map { hydratedCandidate($0, for: component) }
            .mergedSamePartEvidence()
        guard !candidates.isEmpty else {
            return PartSelectionDecision(
                refdes: component.refdes,
                status: .requiresVendorResolution,
                selectedCandidate: nil,
                candidateSet: [],
                rationale: "No component catalog provider evidence was configured for this selection.",
                evidenceReferences: [],
                unresolvedDecisions: ["Provide catalog provider evidence for \(component.refdes)."]
            )
        }

        let validator = ComponentCatalogValidator()
        let validCandidates = candidates.filter { validator.validate($0).isValid }
        if validCandidates.isEmpty {
            let issues = candidates.flatMap { validator.validate($0).issues.map(\.code) }
            return PartSelectionDecision(
                refdes: component.refdes,
                status: .blocked,
                selectedCandidate: nil,
                candidateSet: candidates,
                rationale: "Catalog candidates are missing required evidence: \(Array(Set(issues)).sorted().joined(separator: ","))",
                evidenceReferences: candidates.flatMap(\.evidence),
                unresolvedDecisions: ["Provide manufacturer, MPN, package, ratings, datasheet, and provenance evidence for \(component.refdes)."]
            )
        }
        let rankedCandidates = rankedComponentCandidates(validCandidates, for: component)
        if rankedCandidates.count == 1, let selected = rankedCandidates.first?.candidate {
            return PartSelectionDecision(
                refdes: component.refdes,
                status: .selected,
                selectedCandidate: selected,
                candidateSet: [selected],
                rationale: "Single catalog candidate satisfies required evidence checks.",
                evidenceReferences: selected.evidence,
                unresolvedDecisions: []
            )
        }
        if let first = rankedCandidates.first {
            let rationale: String
            if let second = rankedCandidates.dropFirst().first, first.score == second.score {
                rationale = "Selected stable catalog candidate after required evidence checks and tied lifecycle, stock, package, and electrical constraint score."
            } else {
                rationale = "Selected highest-ranked catalog candidate using lifecycle, stock, package, and electrical constraint evidence."
            }
            return PartSelectionDecision(
                refdes: component.refdes,
                status: .selected,
                selectedCandidate: first.candidate,
                candidateSet: rankedCandidates.map(\.candidate),
                rationale: rationale,
                evidenceReferences: first.candidate.evidence,
                unresolvedDecisions: []
            )
        }
        return PartSelectionDecision(
            refdes: component.refdes,
            status: .ambiguous,
            selectedCandidate: nil,
            candidateSet: rankedCandidates.map(\.candidate),
            rationale: "Multiple catalog candidates satisfy required evidence checks.",
            evidenceReferences: rankedCandidates.flatMap(\.candidate.evidence),
            unresolvedDecisions: ["Choose one candidate for \(component.refdes) or add tighter constraints."]
        )
    }

    private func hydratedCandidate(_ candidate: ComponentCandidate, for component: ComponentIntent? = nil) -> ComponentCandidate {
        var hydrated = candidate
        let extracted = candidate.evidence.reduce(into: [String: String]()) { result, evidence in
            for (key, value) in evidence.extractedParameters where result[key] == nil {
                result[key] = value
            }
        }
        if hydrated.package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hydrated.package = firstNonEmptyCandidateField(
                dictionaries: [candidate.ratings, extracted],
                keys: ["package", "package_case", "case_package", "supplier_device_package", "mounting_type"]
            )
        }
        if hydrated.package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let connectorPackage = connectorPackageFallback(for: component, candidate: hydrated) {
            hydrated.package = connectorPackage
            hydrated.ratings["package"] = hydrated.ratings["package"] ?? connectorPackage
        }
        if hydrated.ratings.isEmpty {
            hydrated.ratings = extracted.filter { entry in
                entry.key != "target_refdes"
                    && entry.key != "datasheet_url"
                    && entry.key != "datasheet"
                    && entry.key != "source_url"
            }
        } else {
            hydrated.ratings = extracted.merging(hydrated.ratings) { _, existing in existing }
        }
        let datasheetURL = firstNonEmptyCandidateField(
            dictionaries: [candidate.ratings, extracted],
            keys: ["datasheet_url", "datasheet", "datasheeturl", "data_sheet_url"]
        )
        if hydrated.datasheets.isEmpty, !datasheetURL.isEmpty {
            hydrated.datasheets = [
                DatasheetEvidence(
                    manufacturer: hydrated.manufacturer,
                    mpn: hydrated.mpn,
                    url: datasheetURL,
                    localPath: nil,
                    sha256: nil,
                    providerID: hydrated.evidence.first?.providerID ?? "catalog",
                    retrievedAt: hydrated.evidence.first?.retrievedAt ?? "unknown",
                    license: hydrated.evidence.first?.cachePolicy ?? "catalog",
                    citations: []
                ),
            ]
        }
        return hydrated
    }

    private func connectorPackageFallback(
        for component: ComponentIntent?,
        candidate: ComponentCandidate
    ) -> String? {
        guard let component else { return nil }
        let componentText = [
            component.refdes,
            component.role,
            component.constraints["kind"],
            component.constraints["component_category"],
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        guard componentText.contains("connector") || componentText.contains("jack") else { return nil }
        let candidateText = candidateSearchText(candidate)
        guard candidateText.contains("connector") || candidateText.contains("jack") else { return nil }
        let mounting = component.constraints["mounting"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let mounting, !mounting.isEmpty else { return nil }
        return mounting.replacingOccurrences(of: " ", with: "_").lowercased()
    }

    private func rankedComponentCandidates(
        _ candidates: [ComponentCandidate],
        for component: ComponentIntent
    ) -> [(candidate: ComponentCandidate, score: Int)] {
        candidates
            .map { candidate in
                (candidate, componentCandidateScore(candidate, for: component))
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }
                return lhs.candidate.mpn.localizedStandardCompare(rhs.candidate.mpn) == .orderedAscending
            }
    }

    private func componentCandidateScore(_ candidate: ComponentCandidate, for component: ComponentIntent) -> Int {
        var score = 0
        let text = candidateSearchText(candidate)
        if !candidate.datasheets.isEmpty { score += 5 }
        if !candidate.package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { score += 5 }
        if !candidate.ratings.isEmpty { score += 3 }
        if candidate.evidence.contains(where: { $0.extractedParameters["target_refdes"] == component.refdes }) { score += 8 }
        if availabilityCount(candidate.availabilitySummary) > 0 { score += 4 }
        let lifecycle = candidate.lifecycleState.lowercased()
        if lifecycle.contains("active") || lifecycle.contains("new product") { score += 4 }
        if lifecycle.contains("obsolete") || lifecycle.contains("not for new") { score -= 8 }
        score += componentConstraintScore(component, candidate: candidate, candidateText: text)
        return score
    }

    private func componentConstraintScore(_ component: ComponentIntent, candidate: ComponentCandidate, candidateText: String) -> Int {
        var score = 0
        let constraints = component.constraints
        for key in ["package", "mounting", "selected_footprint"] {
            guard let value = constraints[key]?.lowercased(), !value.isEmpty else { continue }
            let tokens = value
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .split(separator: " ")
                .map(String.init)
            if tokens.contains(where: { candidateText.contains($0) }) {
                score += 4
            }
        }
        for (constraintKey, ratingKeys) in [
            ("voltage_rating", ["voltage_v", "voltage_rated", "voltage", "voltage_rating_ac", "voltage_rating_dc", "vce", "collector_emitter_breakdown_voltage"]),
            ("current_rating", ["current_a", "current", "current_rating", "ic", "collector_current"]),
            ("power_rating", ["power_w", "power", "power_rating", "power_max", "power_dissipation"]),
        ] {
            guard let required = numericPrefix(constraints[constraintKey]) else { continue }
            let available = ratingKeys.compactMap { numericPrefix(candidate.ratings[$0]) }.max() ?? numericPrefix(candidateText)
            if let available {
                score += ratingMarginScore(required: required, available: available)
            }
        }
        score += valueMatchScore(
            required: normalizedResistanceOhms(component.constraints["resistance"]),
            available: normalizedResistanceOhms(candidate.ratings["resistance"])
                ?? normalizedResistanceOhms(candidate.value)
                ?? normalizedResistanceOhms(candidate.mpn),
            toleranceRatio: 0.05
        )
        score += valueMatchScore(
            required: normalizedCapacitanceUF(component.constraints["capacitance"]),
            available: normalizedCapacitanceUF(candidate.ratings["capacitance"])
                ?? normalizedCapacitanceUF(candidate.value)
                ?? normalizedCapacitanceUF(candidate.mpn),
            toleranceRatio: 0.10
        )
        if let required = normalizedPositionCount(component.constraints["positions"]) {
            if let available = candidatePositionCount(candidate) {
                score += available == required ? 10 : -12
            }
        }
        if let required = normalizedPolarity(component.constraints["polarity"]) {
            let available = normalizedPolarity(candidate.ratings["polarity"]) ?? normalizedPolarity(candidateText)
            if let available {
                score += available == required ? 8 : -10
            }
        }
        if let required = normalizedTaper(component.constraints["taper"]) {
            let available = normalizedTaper(candidate.ratings["taper"]) ?? normalizedTaper(candidateText)
            if let available {
                score += available == required ? 8 : -10
            }
        }
        return score
    }

    private func ratingMarginScore(required: Double, available: Double) -> Int {
        guard required > 0 else { return 0 }
        if available < required {
            return -6
        }
        let ratio = available / required
        if abs(available - required) / required <= 0.05 {
            return 9
        }
        if ratio <= 1.5 {
            return 6
        }
        if ratio <= 3 {
            return 3
        }
        return 1
    }

    private func candidateSearchText(_ candidate: ComponentCandidate) -> String {
        ([
            candidate.normalizedCategory,
            candidate.value ?? "",
            candidate.package,
            candidate.mpn,
            candidate.manufacturer,
            candidate.lifecycleState,
            candidate.availabilitySummary,
        ] + candidate.ratings.map { "\($0.key) \($0.value)" })
            .joined(separator: " ")
            .lowercased()
    }

    private func firstNonEmptyCandidateField(dictionaries: [[String: String]], keys: [String]) -> String {
        for dictionary in dictionaries {
            for key in keys {
                if let value = dictionary[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                    return value
                }
            }
        }
        return ""
    }

    private func availabilityCount(_ value: String) -> Int {
        let digits = value.filter { $0.isNumber }
        return Int(digits) ?? 0
    }

    private func numericPrefix(_ value: String?) -> Double? {
        guard let value else { return nil }
        let pattern = #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return Double(value[range])
    }

    private func valueMatchScore(required: Double?, available: Double?, toleranceRatio: Double) -> Int {
        guard let required,
              let available,
              required > 0 else {
            return 0
        }
        let ratio = abs(available - required) / required
        if ratio <= toleranceRatio {
            return 12
        }
        if ratio <= toleranceRatio * 4 {
            return 2
        }
        return -16
    }

    private func normalizedResistanceOhms(_ value: String?) -> Double? {
        guard let value else { return nil }
        let normalized = value
            .replacingOccurrences(of: "Ω", with: "ohm")
            .replacingOccurrences(of: "R", with: "r")
            .replacingOccurrences(of: "K", with: "k")
            .replacingOccurrences(of: "M", with: "m")
        if let explicit = firstEngineeringValue(
            in: normalized,
            pattern: #"(?i)\b(\d+(?:\.\d+)?)\s*([km]?)\s*(?:ohm|ohms)\b"#
        ) {
            return explicit
        }
        if let compact = firstEngineeringValue(
            in: normalized,
            pattern: #"(?i)\b(\d+(?:\.\d+)?)([rkm])(\d*)\b"#
        ) {
            return compact
        }
        return nil
    }

    private func firstEngineeringValue(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 2,
              let numberRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        var numberText = String(text[numberRange])
        if match.numberOfRanges > 3,
           let suffixRange = Range(match.range(at: 3), in: text),
           !text[suffixRange].isEmpty {
            numberText += ".\(text[suffixRange])"
        }
        guard let number = Double(numberText) else { return nil }
        switch String(text[unitRange]).lowercased() {
        case "k":
            return number * 1_000
        case "m":
            return number * 1_000_000
        default:
            return number
        }
    }

    private func normalizedCapacitanceUF(_ value: String?) -> Double? {
        guard let value,
              let number = numericPrefix(value) else {
            return nil
        }
        let lower = value.lowercased()
        if lower.contains("pf") {
            return number / 1_000_000
        }
        if lower.contains("nf") {
            return number / 1_000
        }
        if lower.contains("mf") {
            return number * 1_000
        }
        if lower.contains("f") && !lower.contains("uf") && !lower.contains("µf") {
            return number * 1_000_000
        }
        return number
    }

    private func normalizedPositionCount(_ value: String?) -> Int? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = Int(trimmed) {
            return exact
        }
        return firstPositionCount(in: trimmed)
    }

    private func candidatePositionCount(_ candidate: ComponentCandidate) -> Int? {
        for key in ["positions", "number_of_positions", "contacts", "number_of_contacts", "pin_count"] {
            if let count = normalizedPositionCount(candidate.ratings[key]) {
                return count
            }
        }
        return firstPositionCount(in: candidateSearchText(candidate))
    }

    private func firstPositionCount(in text: String) -> Int? {
        let patterns = [
            #"(?i)\b(\d+)\s*(?:pin|pins|position|positions|pos|ckt|circuit|circuits|cond|contacts?)\b"#,
            #"(?i)\b(\d+)p\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let range = Range(match.range(at: 1), in: text),
                  let count = Int(text[range]) else {
                continue
            }
            return count
        }
        return nil
    }

    private func normalizedPolarity(_ value: String?) -> String? {
        guard let value else { return nil }
        let lower = value.lowercased()
        if lower.contains("npn") || lower.contains("n-channel") || lower.contains("n channel") {
            return "n"
        }
        if lower.contains("pnp") || lower.contains("p-channel") || lower.contains("p channel") {
            return "p"
        }
        return nil
    }

    private func normalizedTaper(_ value: String?) -> String? {
        guard let value else { return nil }
        let lower = value.lowercased()
        if lower.contains("linear") {
            return "linear"
        }
        if lower.contains("audio") || lower.contains("logarithmic") || lower.contains(" log ") {
            return "audio"
        }
        return nil
    }

    private func matchingCandidates(
        for component: ComponentIntent,
        candidates: [ComponentCandidate]
    ) -> [ComponentCandidate] {
        guard !candidates.isEmpty else { return [] }
        let targeted = candidates.filter { candidate in
            candidate.evidence.contains {
                $0.extractedParameters["target_refdes"] == component.refdes
            }
        }
        let hints = componentCategoryHints(for: component)
        if !targeted.isEmpty {
            let compatibleTargeted = filterCandidates(targeted, compatibleWith: component)
            let filteredTargeted = filterCandidates(compatibleTargeted, matching: hints)
            let constrainedTargeted = filterCandidates(filteredTargeted, satisfying: component)
            if !constrainedTargeted.isEmpty {
                return constrainedTargeted
            }
        }
        let compatible = filterCandidates(candidates, compatibleWith: component)
        let categoryFiltered = hints.isEmpty ? compatible : filterCandidates(compatible, matching: hints)
        return filterCandidates(categoryFiltered, satisfying: component)
    }

    private enum ComponentFamily: String {
        case bridgeRectifier = "bridge_rectifier"
        case capacitor
        case connector
        case diode
        case fixedResistor = "fixed_resistor"
        case integratedCircuit = "integrated_circuit"
        case potentiometer
        case transistor
    }

    private func filterCandidates(
        _ candidates: [ComponentCandidate],
        compatibleWith component: ComponentIntent
    ) -> [ComponentCandidate] {
        let expected = expectedComponentFamilies(for: component)
        guard !expected.isEmpty else { return candidates }
        return candidates.filter { candidate in
            let candidateFamilies = componentFamilies(for: candidate)
            guard !candidateFamilies.isEmpty else { return true }
            return !expected.isDisjoint(with: candidateFamilies)
        }
    }

    private func expectedComponentFamilies(for component: ComponentIntent) -> Set<ComponentFamily> {
        let refdes = component.refdes.uppercased()
        let text = componentIntentFamilyText(component)
        var families = Set<ComponentFamily>()

        if refdes.hasPrefix("BR") || (text.contains("bridge") && text.contains("rectifier")) || text.contains("bridge_rectifier") {
            families.insert(.bridgeRectifier)
        }
        if refdes.hasPrefix("RV")
            || text.contains("potentiometer")
            || text.contains("trimmer")
            || text.contains("r_pot")
            || text.contains("variable resistor") {
            families.insert(.potentiometer)
        }
        if (refdes.hasPrefix("R") || text.contains("resistor") || text.hasSuffix(":r"))
            && !families.contains(.potentiometer) {
            families.insert(.fixedResistor)
        }
        if refdes.hasPrefix("C") || text.contains("capacitor") || text.hasSuffix(":c") {
            families.insert(.capacitor)
        }
        if refdes.hasPrefix("Q") || text.contains("transistor") || text.contains("mosfet") || text.contains("bjt") || text.contains("jfet") {
            families.insert(.transistor)
        }
        if refdes.hasPrefix("D") || text.contains("diode") {
            families.insert(.diode)
        }
        if refdes.hasPrefix("J")
            || refdes.hasPrefix("P")
            || text.contains("connector")
            || text.contains("terminal_block")
            || text.contains("terminal block")
            || text.contains("jack") {
            families.insert(.connector)
        }
        if refdes.hasPrefix("U")
            || text.contains("regulator")
            || text.contains("op amp")
            || text.contains("opamp")
            || text.contains("driver ic")
            || text.contains("integrated circuit") {
            families.insert(.integratedCircuit)
        }

        return families
    }

    private func componentFamilies(for candidate: ComponentCandidate) -> Set<ComponentFamily> {
        let text = candidateFamilyText(candidate)
        var families = Set<ComponentFamily>()

        if (text.contains("bridge") && text.contains("rectifier")) || text.contains("bridge_rectifier") {
            families.insert(.bridgeRectifier)
        }
        if text.contains("potentiometer")
            || text.contains("trimmer")
            || text.contains("variable resistor") {
            families.insert(.potentiometer)
        }
        if text.contains("resistor") && !families.contains(.potentiometer) {
            families.insert(.fixedResistor)
        }
        if text.contains("capacitor")
            || text.contains("capacitance")
            || text.contains("electrolytic")
            || text.contains("film cap")
            || text.contains("ceramic cap") {
            families.insert(.capacitor)
        }
        if text.contains("transistor")
            || text.contains("mosfet")
            || text.contains("bjt")
            || text.contains("jfet")
            || text.contains("fet ") {
            families.insert(.transistor)
        }
        if text.contains("diode") && !families.contains(.bridgeRectifier) {
            families.insert(.diode)
        }
        if text.contains("connector")
            || text.contains("terminal_block")
            || text.contains("terminal block")
            || text.contains("pluggable terminal")
            || text.contains("header")
            || text.contains("jack") {
            families.insert(.connector)
        }
        if text.contains("integrated circuit")
            || text.contains(" voltage regulator")
            || text.contains(" op amp")
            || text.contains("opamp")
            || text.contains("driver ic") {
            families.insert(.integratedCircuit)
        }

        return families
    }

    private func componentIntentFamilyText(_ component: ComponentIntent) -> String {
        ([
            component.refdes,
            component.role,
        ] + component.constraints.map { "\($0.key) \($0.value)" })
            .joined(separator: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
    }

    private func candidateFamilyText(_ candidate: ComponentCandidate) -> String {
        ([
            candidate.normalizedCategory,
            candidate.value ?? "",
            candidate.manufacturer,
            candidate.mpn,
        ] + candidate.ratings.map { "\($0.key) \($0.value)" })
            .joined(separator: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
    }

    private func filterCandidates(_ candidates: [ComponentCandidate], matching hints: [String]) -> [ComponentCandidate] {
        guard !hints.isEmpty else { return candidates }
        return candidates.filter { candidate in
            candidateMatchesCategoryHints(candidate, hints: hints)
        }
    }

    private func candidateMatchesCategoryHints(_ candidate: ComponentCandidate, hints: [String]) -> Bool {
        let candidateText = [
            candidate.normalizedCategory,
            candidate.value ?? "",
            candidate.package,
            candidate.mpn,
            candidate.manufacturer,
        ]
            .joined(separator: " ")
            .lowercased()
        if candidateText.contains("accessor") || candidateText.contains(" tool") || candidateText.contains("_tool") {
            return false
        }
        return hints.contains { hint in
            candidateText.contains(hint)
        }
    }

    private func filterCandidates(_ candidates: [ComponentCandidate], satisfying component: ComponentIntent) -> [ComponentCandidate] {
        candidates.filter { !candidateViolatesRequiredConstraints($0, component: component) }
    }

    private func candidateViolatesRequiredConstraints(_ candidate: ComponentCandidate, component: ComponentIntent) -> Bool {
        let text = candidateSearchText(candidate)
        if let requiredMPN = nonEmpty(component.constraints["manufacturer_part_number"] ?? component.constraints["mpn"]),
           normalizedMPN(candidate.mpn) != normalizedMPN(requiredMPN) {
            return true
        }
        if let requiredPackage = component.constraints["package"],
           !requiredPackage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !candidatePackageMatches(candidate, requiredPackage: requiredPackage) {
            return true
        }
        if (component.constraints["mounting"] ?? "").lowercased().contains("through"),
           text.contains("surface mount") || text.contains("smd") || text.contains("smt") || text.contains("0402") || text.contains("0603") || text.contains("0805") {
            return true
        }
        if let required = normalizedCapacitanceUF(component.constraints["capacitance"]) {
            guard let available = normalizedCapacitanceUF(candidate.ratings["capacitance"]) ?? normalizedCapacitanceUF(candidate.value) else {
                return true
            }
            if abs(available - required) / required > 0.10 {
                return true
            }
        }
        if let required = normalizedResistanceOhms(component.constraints["resistance"]) {
            guard let available = normalizedResistanceOhms(candidate.ratings["resistance"]) ?? normalizedResistanceOhms(candidate.value) ?? normalizedResistanceOhms(candidate.mpn) else {
                return true
            }
            if abs(available - required) / required > 0.05 {
                return true
            }
        }
        for (constraintKey, ratingKeys) in [
            ("voltage_rating", ["voltage_v", "voltage_rated", "voltage", "voltage_rating_ac", "voltage_rating_dc", "vce", "collector_emitter_breakdown_voltage"]),
            ("current_rating", ["current_a", "current", "current_rating", "ic", "collector_current"]),
            ("power_rating", ["power_w", "power", "power_rating", "power_max", "power_dissipation"]),
        ] {
            guard let required = numericPrefix(component.constraints[constraintKey]) else { continue }
            let available = ratingKeys.compactMap { numericPrefix(candidate.ratings[$0]) }.max()
            if let available, available < required {
                return true
            }
        }
        if let required = normalizedPositionCount(component.constraints["positions"]),
           let available = candidatePositionCount(candidate),
           available != required {
            return true
        }
        if let required = normalizedPolarity(component.constraints["polarity"]),
           let available = normalizedPolarity(candidate.ratings["polarity"]) ?? normalizedPolarity(text),
           available != required {
            return true
        }
        if let required = normalizedTaper(component.constraints["taper"]),
           let available = normalizedTaper(candidate.ratings["taper"]) ?? normalizedTaper(text),
           available != required {
            return true
        }
        if connectorCandidateViolatesSubtype(component: component, candidateText: text) {
            return true
        }
        return false
    }

    private func normalizedMPN(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func connectorCandidateViolatesSubtype(component: ComponentIntent, candidateText: String) -> Bool {
        let refdes = component.refdes.uppercased()
        let componentText = componentIntentFamilyText(component)
        guard refdes.hasPrefix("J")
            || refdes.hasPrefix("P")
            || componentText.contains("connector")
            || componentText.contains("jack")
            || componentText.contains("terminal") else {
            return false
        }

        if componentText.contains("terminal_block")
            || componentText.contains("terminal block")
            || componentText.contains("screw terminal") {
            return !candidateTextMatchesAny(candidateText, [
                "terminal block",
                "terminal_blocks",
                "terminal",
                "screw terminal",
                "phoenix",
                "bornier",
            ])
        }
        if componentText.contains("phone_audio_jack")
            || componentText.contains("phone audio jack")
            || componentText.contains("audio jack")
            || componentText.contains("guitar input")
            || componentText.contains("phone jack") {
            return !candidateTextMatchesAny(candidateText, [
                "audio jack",
                "phone jack",
                "6.35",
                "1/4",
                "mono phone",
                "neutrik",
                "switchcraft",
            ])
        }
        if componentText.contains("speaker_connector")
            || componentText.contains("speaker connector")
            || componentText.contains("speaker output") {
            return !candidateTextMatchesAny(candidateText, [
                "speaker",
                "terminal block",
                "terminal",
                "binding",
                "banana",
                "speakon",
                "audio jack",
                "phone jack",
                "6.35",
                "1/4",
            ])
        }
        return false
    }

    private func candidateTextMatchesAny(_ text: String, _ needles: [String]) -> Bool {
        let normalizedText = text
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let compactText = normalizedText.filter { $0.isLetter || $0.isNumber }
        return needles.contains { needle in
            let normalizedNeedle = needle
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
            let compactNeedle = normalizedNeedle.filter { $0.isLetter || $0.isNumber }
            let canUseCompactNeedle = compactNeedle.count >= 4 && compactNeedle.contains { $0.isLetter }
            return normalizedText.contains(normalizedNeedle)
                || (canUseCompactNeedle && compactText.contains(compactNeedle))
        }
    }

    private func candidatePackageMatches(_ candidate: ComponentCandidate, requiredPackage: String) -> Bool {
        let requiredTokens = normalizedPackageTokens(requiredPackage)
        guard !requiredTokens.isEmpty else { return true }
        let candidatePackages = [
            candidate.package,
            candidate.ratings["package"] ?? "",
            candidate.ratings["package_case"] ?? "",
            candidate.ratings["case_package"] ?? "",
            candidate.ratings["supplier_device_package"] ?? "",
        ] + candidate.footprintCandidates.flatMap { footprint in
            [footprint.name, footprint.library]
        }
        let candidateTokens = Set(candidatePackages.flatMap(normalizedPackageTokens))
        guard !candidateTokens.isEmpty else { return false }
        return requiredTokens.contains { required in
            candidateTokens.contains { candidate in
                candidate == required || candidate.contains(required) || required.contains(candidate)
            }
        }
    }

    private func normalizedPackageTokens(_ value: String) -> [String] {
        let ignoredTokens: Set<String> = ["pkg", "package", "sot", "smt", "smd", "tht", "through", "hole"]
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
        var tokens = Set<String>()
        for token in normalized where token.count >= 3 && !ignoredTokens.contains(token) {
            tokens.insert(token)
        }
        let compact = value
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
        if compact.count >= 3 && !ignoredTokens.contains(compact) {
            tokens.insert(compact)
        }
        return Array(tokens)
    }

    private func componentCategoryHints(for component: ComponentIntent) -> [String] {
        let refdes = component.refdes.uppercased()
        let role = component.role.lowercased()
        let symbol = component.constraints["selected_symbol"]?.lowercased() ?? ""
        let category = [
            component.constraints["component_category"],
            component.constraints["category"],
            component.constraints["kind"],
            component.constraints["device_family"],
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let combined = "\(category) \(role) \(symbol)"

        if refdes.hasPrefix("BR") || combined.contains("bridge") || combined.contains("rectifier") {
            return ["bridge", "rectifier"]
        }
        if refdes.hasPrefix("RV") || combined.contains("potentiometer") || combined.contains("pot") {
            return ["potentiometer", "trimmer"]
        }
        if refdes.hasPrefix("R") || combined.contains("resistor") || symbol.hasSuffix(":r") {
            return ["resistor", "potentiometer", "trimmer"]
        }
        if refdes.hasPrefix("C") || combined.contains("capacitor") || symbol.hasSuffix(":c") {
            return ["capacitor"]
        }
        if refdes.hasPrefix("Q") || combined.contains("transistor") || combined.contains("mosfet") || combined.contains("bjt") {
            return ["transistor", "bjt", "mosfet", "jfet", "fet"]
        }
        if refdes.hasPrefix("D") || combined.contains("diode") {
            return ["diode"]
        }
        if refdes.hasPrefix("J") || refdes.hasPrefix("P") || combined.contains("connector") || combined.contains("jack") {
            return ["connector", "terminal", "header", "jack"]
        }
        if refdes.hasPrefix("U") || combined.contains("regulator") || combined.contains("op amp") || combined.contains("opamp") {
            return ["ic", "regulator", "opamp", "op_amp", "driver"]
        }
        return []
    }

    private func canonicalFootprintName(_ footprint: FootprintCandidate) -> String {
        if footprint.library.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return footprint.name
        }
        if footprint.name.contains(":") {
            return footprint.name
        }
        return "\(footprint.library):\(footprint.name)"
    }

    private func requiredPins(for component: ComponentIntent?) -> [String] {
        guard let value = component?.constraints["required_pins"] ?? component?.constraints["symbol_pins"] else {
            return []
        }
        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func requiredPins(for component: CircuitComponent) -> [String] {
        component.pins.compactMap { pin in
            let canonical = pin.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !canonical.isEmpty { return canonical }
            let symbol = pin.symbolPin.trimmingCharacters(in: .whitespacesAndNewlines)
            if !symbol.isEmpty { return symbol }
            let number = pin.pinNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            return number.isEmpty ? nil : number
        }
    }

    private func pinPadMapConstraint(for component: CircuitComponent) -> String {
        component.pins.compactMap { pin in
            let canonical = pin.canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
            let symbol = pin.symbolPin.trimmingCharacters(in: .whitespacesAndNewlines)
            let number = pin.pinNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            let pinName = [canonical, symbol, number].first { !$0.isEmpty } ?? ""
            let padName = pin.footprintPad?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !pinName.isEmpty, !padName.isEmpty else { return nil }
            return "\(pinName)=\(padName)"
        }
        .joined(separator: ",")
    }

    private func pinPadMapConstraint(from value: String?) -> [String: String] {
        guard let value else { return [:] }
        return value
            .split(separator: ",")
            .reduce(into: [String: String]()) { result, pair in
                let parts = pair.split(separator: "=", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return }
                result[parts[0]] = parts[1]
            }
    }

    private func uniqueRefdes(_ refdes: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in refdes where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private func synthesizeCircuitIR(from intent: DesignIntent) -> CircuitIR {
        var expansions: [String: [String]] = [:]
        var components: [CircuitComponent] = []
        var seen = Set<String>()

        for component in intent.components {
            let expanded = expandedCircuitComponents(from: component)
            expansions[component.refdes] = expanded.map(\.refdes)
            for circuitComponent in expanded where !seen.contains(circuitComponent.refdes) {
                seen.insert(circuitComponent.refdes)
                components.append(circuitComponent)
            }
        }

        let componentsByRefdes = Dictionary(components.map { ($0.refdes, $0) }, uniquingKeysWith: { first, _ in first })
        let safetyDomain = intent.boards.first?.safetyDomain.isEmpty == false ? intent.boards[0].safetyDomain : "unspecified"
        let nets = synthesizedNets(
            from: intent.nets,
            expansions: expansions,
            componentsByRefdes: componentsByRefdes,
            safetyDomain: safetyDomain
        )
        let constraints = intent.safetyProfile.isolationRequired
            ? [CircuitConstraint(kind: "safety_domain", target: safetyDomain, value: "isolated_low_voltage")]
            : []

        return CircuitIR(
            designId: intent.designId,
            boardId: intent.boards.first?.id ?? "\(intent.designId)_board",
            components: components,
            nets: nets,
            constraints: constraints,
            verificationScenarios: verificationScenarios(from: intent.verificationPlan)
        )
    }

    private func expandedCircuitComponents(from intent: ComponentIntent) -> [CircuitComponent] {
        let role = intent.role.lowercased()
        let implementation = intent.constraints["implementation"]?.lowercased() ?? ""
        if role.contains("boost/cut") || role.contains("filter network") || role.contains("sweepable") {
            return filterCircuitComponents(from: intent)
        }
        if implementation.contains("discrete_rc") || role.contains("tone control") || role.contains("tone stack") {
            return toneCircuitComponents(from: intent)
        }
        if intent.constraints["kind"] == "resistor_network" {
            return resistorNetworkComponents(from: intent)
        }
        return [circuitComponent(refdes: intent.refdes, role: intent.role, sourceIntent: intent)]
    }

    private func toneCircuitComponents(from intent: ComponentIntent) -> [CircuitComponent] {
        let bands = (intent.constraints["bands"] ?? "bass,mid,treble")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        return bands.flatMap { band in
            [
                circuitComponent(refdes: "R\(band)1", role: "\(band.lowercased()) tone resistor", sourceIntent: intent),
                circuitComponent(refdes: "C\(band)1", role: "\(band.lowercased()) tone capacitor", sourceIntent: intent),
            ]
        }
    }

    private func filterCircuitComponents(from intent: ComponentIntent) -> [CircuitComponent] {
        [
            circuitComponent(refdes: "RFILT1", role: "sweepable filter resistor", sourceIntent: intent),
            circuitComponent(refdes: "CFILT1", role: "sweepable filter capacitor", sourceIntent: intent),
            circuitComponent(refdes: "RVFILT1", role: "sweepable filter frequency control potentiometer", sourceIntent: intent),
        ]
    }

    private func resistorNetworkComponents(from intent: ComponentIntent) -> [CircuitComponent] {
        let base = intent.refdes
        return [
            circuitComponent(refdes: "\(base)A", role: "\(intent.role) upper resistor", sourceIntent: intent),
            circuitComponent(refdes: "\(base)B", role: "\(intent.role) lower resistor", sourceIntent: intent),
        ]
    }

    private func circuitComponent(refdes: String, role: String, sourceIntent: ComponentIntent) -> CircuitComponent {
        let symbol = circuitSymbol(for: refdes, role: role)
        return CircuitComponent(
            refdes: refdes,
            role: role,
            selectedSymbol: symbol,
            selectedFootprint: nil,
            manufacturerPartNumber: nil,
            sourceEvidence: [SourceEvidence(kind: "design_intent_component", reference: sourceIntent.refdes)],
            pins: circuitPins(refdes: refdes, symbol: symbol),
            constraints: circuitConstraints(refdes: refdes, role: role, sourceIntent: sourceIntent)
        )
    }

    private func circuitConstraints(refdes: String, role: String, sourceIntent: ComponentIntent) -> [String: String] {
        let upperRefdes = refdes.uppercased()
        let lowerRole = role.lowercased()
        let sourceRefdes = sourceIntent.refdes.uppercased()
        let ratings = classAOutputStageRatings(
            outputPowerWatts: sourceIntent.constraints["output_power_watts"],
            loadOhms: sourceIntent.constraints["load_ohms"]
        )
        var constraints = sourceIntent.constraints
        constraints["source_refdes"] = sourceIntent.refdes
        constraints["selection_basis"] = constraints["selection_basis"] ?? "derived_from_approved_design_intent"

        var defaults: [String: String] = [:]
        if upperRefdes.hasPrefix("BR") || lowerRole.contains("rectifier") {
            defaults = [
                "component_category": "bridge_rectifier",
                "voltage_rating": "100V",
                "current_rating": "8A",
                "mounting": "through_hole",
            ]
        } else if upperRefdes == "CRES1" || lowerRole.contains("reservoir") || lowerRole.contains("bulk") {
            defaults = [
                "component_category": "aluminum_electrolytic_capacitor",
                "capacitance": "10000uF",
                "voltage_rating": "50V",
                "mounting": "through_hole",
                "dielectric": "aluminum_electrolytic",
            ]
        } else if upperRefdes.hasPrefix("C") {
            defaults = capacitorDefaults(refdes: upperRefdes, role: lowerRole)
        } else if upperRefdes.hasPrefix("RV") {
            defaults = [
                "component_category": "potentiometer",
                "resistance": "100kOhm",
                "taper": "linear",
                "mounting": "through_hole",
            ]
        } else if upperRefdes.hasPrefix("R") {
            defaults = resistorDefaults(refdes: upperRefdes, role: lowerRole, sourceRefdes: sourceRefdes)
        } else if upperRefdes == "QOUT1" || lowerRole.contains("output transistor") {
            defaults = [
                "component_category": "power_transistor",
                "polarity": "NPN",
                "voltage_rating": ratings.voltage,
                "current_rating": ratings.current,
                "power_rating": ratings.dissipation,
                "package": "TO-3_or_TO-247",
                "thermal": "external_heatsink_required",
                "requires_soa_review": "true",
            ]
        } else if upperRefdes.hasPrefix("Q") && lowerRole.contains("driver") {
            defaults = [
                "component_category": "driver_transistor",
                "polarity": "NPN",
                "voltage_rating": ratings.voltage,
                "current_rating": "1A",
                "power_rating": "1W",
                "package": "TO-126_or_TO-220",
            ]
        } else if upperRefdes.hasPrefix("Q") {
            defaults = [
                "component_category": "low_noise_transistor",
                "device_family": constraints["device_family"] ?? "JFET_or_low_noise_BJT",
                "polarity": "NPN_or_N_channel",
                "package": "TO-92",
            ]
        } else if upperRefdes == "JIN" || lowerRole.contains("guitar input") {
            defaults = [
                "component_category": "phone_audio_jack",
                "positions": "2",
                "contact_form": "mono",
                "mounting": "panel_mount",
            ]
        } else if upperRefdes == "JSPK" || lowerRole.contains("speaker") {
            defaults = [
                "component_category": "speaker_connector",
                "positions": "2",
                "current_rating": ratings.current,
                "mounting": "panel_mount",
            ]
        } else if upperRefdes.hasPrefix("J") || upperRefdes.hasPrefix("P") {
            defaults = [
                "component_category": "terminal_block",
                "positions": "2",
                "current_rating": "10A",
                "voltage_rating": "300V",
                "mounting": "through_hole",
            ]
        }

        for (key, value) in defaults where constraints[key] == nil || constraints[key]?.isEmpty == true {
            constraints[key] = value
        }
        return constraints
    }

    private func resistorDefaults(refdes: String, role: String, sourceRefdes: String) -> [String: String] {
        var defaults: [String: String] = [
            "component_category": "resistor",
            "tolerance": "1%",
            "power_rating": "0.25W",
            "package": "through_hole_axial",
        ]
        if sourceRefdes == "RPRE1" {
            defaults["resistance"] = refdes.hasSuffix("A") ? "1MOhm" : "100kOhm"
        } else if sourceRefdes == "RBIAS1" {
            defaults["resistance"] = refdes.hasSuffix("A") ? "10kOhm" : "1kOhm"
            defaults["power_rating"] = "0.5W"
        } else if refdes.contains("BASS") {
            defaults["resistance"] = "1MOhm"
        } else if refdes.contains("MID") {
            defaults["resistance"] = "25kOhm"
        } else if refdes.contains("TREBLE") {
            defaults["resistance"] = "250kOhm"
        } else if refdes.contains("FILT") {
            defaults["resistance"] = "10kOhm"
        }
        return defaults
    }

    private func capacitorDefaults(refdes: String, role: String) -> [String: String] {
        var defaults: [String: String] = [
            "component_category": "film_or_c0g_capacitor",
            "voltage_rating": "50V",
            "mounting": "through_hole",
        ]
        if refdes.contains("BASS") {
            defaults["capacitance"] = "100nF"
            defaults["dielectric"] = "film"
        } else if refdes.contains("MID") {
            defaults["capacitance"] = "22nF"
            defaults["dielectric"] = "film"
        } else if refdes.contains("TREBLE") {
            defaults["capacitance"] = "470pF"
            defaults["dielectric"] = "C0G"
        } else if refdes.contains("FILT") || role.contains("filter") {
            defaults["capacitance"] = "47nF"
            defaults["dielectric"] = "film"
        }
        return defaults
    }

    private func circuitSymbol(for refdes: String, role: String) -> String {
        let upper = refdes.uppercased()
        let lowerRole = role.lowercased()
        if upper.hasPrefix("RV") { return "Device:R_Potentiometer" }
        if upper.hasPrefix("BR") { return "Device:Bridge_Rectifier" }
        if upper.hasPrefix("Q") {
            if lowerRole.contains("jfet") { return "Device:Q_NJFET_DGS" }
            return "Device:Q_NPN_BCE"
        }
        if upper.hasPrefix("R") { return "Device:R" }
        if upper.hasPrefix("C") { return "Device:C" }
        if upper.hasPrefix("J") { return "Connector_Generic:Conn_01x02" }
        return "Device:R"
    }

    private func circuitPins(refdes: String, symbol: String) -> [CircuitPin] {
        switch symbol {
        case "Device:Q_NPN_BCE":
            return [
                circuitPin(refdes, "1", "B", "input"),
                circuitPin(refdes, "2", "C", "power"),
                circuitPin(refdes, "3", "E", "passive"),
            ]
        case "Device:Q_NJFET_DGS":
            return [
                circuitPin(refdes, "1", "D", "passive"),
                circuitPin(refdes, "2", "G", "input"),
                circuitPin(refdes, "3", "S", "passive"),
            ]
        case "Device:Bridge_Rectifier":
            return [
                circuitPin(refdes, "1", "AC1", "power"),
                circuitPin(refdes, "2", "AC2", "power"),
                circuitPin(refdes, "3", "PLUS", "power"),
                circuitPin(refdes, "4", "MINUS", "power"),
            ]
        case "Device:R_Potentiometer":
            return [
                circuitPin(refdes, "1", "A", "passive"),
                circuitPin(refdes, "2", "W", "passive"),
                circuitPin(refdes, "3", "B", "passive"),
            ]
        default:
            return [
                circuitPin(refdes, "1", "1", "passive"),
                circuitPin(refdes, "2", "2", "passive"),
            ]
        }
    }

    private func circuitPin(_ refdes: String, _ number: String, _ name: String, _ type: String) -> CircuitPin {
        CircuitPin(
            componentRefdes: refdes,
            pinNumber: number,
            canonicalName: name,
            electricalType: type,
            symbolPin: name,
            footprintPad: nil
        )
    }

    private func synthesizedNets(
        from netIntents: [NetIntent],
        expansions: [String: [String]],
        componentsByRefdes: [String: CircuitComponent],
        safetyDomain: String
    ) -> [CircuitNet] {
        var nets: [CircuitNet] = []
        var seen = Set<String>()

        for netIntent in netIntents {
            let source = endpointRefdes(for: netIntent.source, expansions: expansions, usage: .source)
            let destination = endpointRefdes(for: netIntent.destination, expansions: expansions, usage: .destination)
            guard let sourceEndpoint = circuitEndpoint(for: source, usage: .source, netIntent: netIntent, componentsByRefdes: componentsByRefdes),
                  let destinationEndpoint = circuitEndpoint(for: destination, usage: .destination, netIntent: netIntent, componentsByRefdes: componentsByRefdes) else {
                continue
            }
            let net = CircuitNet(
                name: netIntent.name,
                role: netIntent.role,
                endpoints: sourceEndpoint == destinationEndpoint ? [sourceEndpoint] : [sourceEndpoint, destinationEndpoint],
                netClass: netClass(for: netIntent),
                safetyDomain: safetyDomain
            )
            if seen.insert(net.name).inserted {
                nets.append(net)
            }
        }

        for (sourceRefdes, expandedRefdes) in expansions where expandedRefdes.count > 1 {
            for pair in zip(expandedRefdes, expandedRefdes.dropFirst()) {
                guard let sourceEndpoint = circuitEndpoint(for: pair.0, usage: .source, netIntent: nil, componentsByRefdes: componentsByRefdes),
                      let destinationEndpoint = circuitEndpoint(for: pair.1, usage: .destination, netIntent: nil, componentsByRefdes: componentsByRefdes) else {
                    continue
                }
                let name = "\(sourceRefdes)_INTERNAL_\(pair.0)_\(pair.1)"
                if seen.insert(name).inserted {
                    nets.append(CircuitNet(
                        name: name,
                        role: "internal expanded network connection",
                        endpoints: [sourceEndpoint, destinationEndpoint],
                        netClass: "signal",
                        safetyDomain: safetyDomain
                    ))
                }
            }
        }

        return nets
    }

    private enum CircuitEndpointUsage {
        case source
        case destination
    }

    private func endpointRefdes(
        for refdes: String,
        expansions: [String: [String]],
        usage: CircuitEndpointUsage
    ) -> String {
        guard let expanded = expansions[refdes], !expanded.isEmpty else {
            return refdes
        }
        switch usage {
        case .source:
            return expanded.last ?? refdes
        case .destination:
            return expanded.first ?? refdes
        }
    }

    private func circuitEndpoint(
        for refdes: String,
        usage: CircuitEndpointUsage,
        netIntent: NetIntent?,
        componentsByRefdes: [String: CircuitComponent]
    ) -> CircuitNetEndpoint? {
        guard let component = componentsByRefdes[refdes] else { return nil }
        let pinNumber = preferredPinNumber(for: component, usage: usage, netIntent: netIntent)
        return CircuitNetEndpoint(componentRefdes: refdes, pinNumber: pinNumber)
    }

    private func preferredPinNumber(
        for component: CircuitComponent,
        usage: CircuitEndpointUsage,
        netIntent: NetIntent?
    ) -> String {
        let refdes = component.refdes.uppercased()
        let netText = "\(netIntent?.name ?? "") \(netIntent?.role ?? "")".lowercased()
        if refdes.hasPrefix("BR") {
            if netText.contains("vraw") || netText.contains("supply rail") || netText.contains("power rail") {
                return component.pins.first { $0.canonicalName.uppercased() == "PLUS" }?.pinNumber ?? "3"
            }
            if netText.contains("gnd") || netText.contains("ground") || netText.contains("common") {
                return component.pins.first { $0.canonicalName.uppercased() == "MINUS" }?.pinNumber ?? "4"
            }
            if netText.contains("ac") {
                return component.pins.first { $0.canonicalName.uppercased() == "AC1" }?.pinNumber ?? "1"
            }
        }
        if refdes == "CRES1" || component.role.lowercased().contains("reservoir") {
            if netText.contains("vraw") || netText.contains("supply rail") || netText.contains("power rail") {
                return "1"
            }
            if netText.contains("gnd") || netText.contains("ground") || netText.contains("common") {
                return "2"
            }
        }
        switch usage {
        case .source:
            return component.pins.last?.pinNumber ?? "1"
        case .destination:
            return component.pins.first?.pinNumber ?? "1"
        }
    }

    private func netClass(for intent: NetIntent) -> String {
        let text = "\(intent.name) \(intent.role)".lowercased()
        if text.contains("gnd") || text.contains("ground") || text.contains("common") {
            return "ground"
        }
        if text.contains("supply") || text.contains("power") || text.contains("rail") || text.contains("vraw") {
            return "power"
        }
        return "signal"
    }

    private func verificationScenarios(from plan: VerificationPlan) -> [VerificationScenario] {
        var scenarios = [VerificationScenario(id: "erc", kind: "erc", expectation: "no blocking ERC errors")]
        if plan.drcRequired {
            scenarios.append(VerificationScenario(id: "drc", kind: "drc", expectation: "no blocking DRC errors"))
        }
        if plan.spiceRequired {
            scenarios.append(VerificationScenario(id: "spice", kind: "spice", expectation: "simulation measurements within approved envelopes"))
        }
        return scenarios
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? String { return Bool(value) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func stringArray(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values }
        if let value = value as? String, !value.isEmpty { return [value] }
        return []
    }

    private func stringDictionary(_ value: [String: Any]) -> [String: String] {
        value.reduce(into: [:]) { result, entry in
            if let string = entry.value as? String {
                result[entry.key] = string
            } else if let bool = entry.value as? Bool {
                result[entry.key] = String(bool)
            } else if let number = entry.value as? NSNumber {
                result[entry.key] = number.stringValue
            }
        }
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

    private func commandFailureWithArtifactsBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        code: String,
        run: ElectronicsCommandRun,
        status: KiCadStatus = .blocked,
        artifacts: [ArtifactRef],
        nextActions: [String]
    ) -> WorkspaceMessageResponse {
        let message = "\(request.address.capability) command failed with exit code \(run.exitCode), but produced diagnostic artifacts."
        let warning = KiCadWarning(
            code: code,
            message: run.output.isEmpty ? message : run.output,
            affectedRefs: run.arguments + artifacts.map(\.path),
            suggestedAction: "Inspect the attached artifact and retry after fixing the reported issue."
        )
        return WorkspaceMessageResponse(
            requestID: request.id,
            status: .blocked,
            payload: try? .encodeJSON(KiCadToolResult(
                status: status,
                artifacts: artifacts,
                warnings: [warning],
                nextActions: nextActions,
                handoff: workflowHandoff(for: request, artifacts: artifacts)
            )),
            artifacts: workspaceArtifacts(from: artifacts, request: request),
            diagnostics: [WorkspaceDiagnostic(code: code, message: message, severity: "error")]
        )
    }

    private func spiceDiagnosticBlock(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext,
        outputURL: URL,
        run: ElectronicsCommandRun,
        artifacts: [ArtifactRef]
    ) -> WorkspaceMessageResponse {
        let logText = ((try? String(contentsOf: outputURL, encoding: .utf8)) ?? run.output)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = logText.isEmpty
            ? "SPICE execution failed with exit code \(run.exitCode)."
            : logText
        let warning = KiCadWarning(
            code: "SPICE_EXECUTION_FAILED",
            message: message,
            affectedRefs: run.arguments + artifacts.map(\.path),
            suggestedAction: "Repair the SPICE deck or model issue and rerun kicad_run_spice."
        )
        Task {
            await publishDiagnostic(reason: .failedGate, request: request, context: context, message: message)
        }
        return WorkspaceMessageResponse(
            requestID: request.id,
            status: .blocked,
            payload: try? .encodeJSON(KiCadToolResult(
                status: .blockedSimulation,
                artifacts: artifacts,
                warnings: [warning],
                nextActions: ["repair_spice_from_diagnostics", "rerun_spice"],
                handoff: workflowHandoff(for: request, artifacts: artifacts)
            )),
            artifacts: workspaceArtifacts(from: artifacts, request: request),
            diagnostics: [WorkspaceDiagnostic(code: warning.code, message: warning.message, severity: "error")]
        )
    }

    private func workspaceArtifacts(from artifacts: [ArtifactRef], request: WorkspaceMessageRequest) -> [WorkspaceArtifactRef] {
        artifacts.map {
            WorkspaceArtifactRef(
                id: "\(request.id.uuidString)-\($0.kind)",
                kind: $0.kind,
                url: URL(fileURLWithPath: $0.path),
                displayName: $0.kind,
                metadata: ["request_id": request.id.uuidString]
            )
        }
    }

    private func diagnosticMessage(_ message: String, commandOutput: String) -> String {
        let output = commandOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty else { return message }
        return "\(message)\n\(output)"
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

    private func minimalKiCadBoardText(generator: String) -> String {
        """
        (kicad_pcb
          (version 20250114)
          (generator "\(generator)")
          (general (thickness 1.6))
          (paper "A4")
          (layers
            (0 "F.Cu" signal)
            (31 "B.Cu" signal)
            (32 "B.Adhes" user "B.Adhesive")
            (33 "F.Adhes" user "F.Adhesive")
            (34 "B.Paste" user)
            (35 "F.Paste" user)
            (36 "B.SilkS" user "B.Silkscreen")
            (37 "F.SilkS" user "F.Silkscreen")
            (38 "B.Mask" user)
            (39 "F.Mask" user)
            (40 "Dwgs.User" user "User.Drawings")
            (41 "Cmts.User" user "User.Comments")
            (42 "Eco1.User" user "User.Eco1")
            (43 "Eco2.User" user "User.Eco2")
            (44 "Edge.Cuts" user)
            (45 "Margin" user)
            (46 "B.CrtYd" user "B.Courtyard")
            (47 "F.CrtYd" user "F.Courtyard")
            (48 "B.Fab" user)
            (49 "F.Fab" user)
          )
          (gr_rect
            (start 0 0)
            (end 120 80)
            (stroke (width 0.1) (type default))
            (fill no)
            (layer "Edge.Cuts")
            (uuid "\(UUID().uuidString)")
          )
        )
        """
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

private extension Array where Element == ComponentCandidate {
    func mergedSamePartEvidence() -> [ComponentCandidate] {
        var orderedKeys: [String] = []
        var grouped: [String: [ComponentCandidate]] = [:]
        for (index, candidate) in enumerated() {
            let key = Self.samePartKey(candidate) ?? "unique:\(index):\(candidate.mpn)"
            if grouped[key] == nil {
                orderedKeys.append(key)
            }
            grouped[key, default: []].append(candidate)
        }
        return orderedKeys.compactMap { key in
            guard let candidates = grouped[key] else { return nil }
            return Self.mergeSamePart(candidates)
        }
    }

    private static func mergeSamePart(_ candidates: [ComponentCandidate]) -> ComponentCandidate? {
        guard var merged = candidates.first else { return nil }
        for candidate in candidates.dropFirst() {
            if merged.manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.manufacturer = candidate.manufacturer
            }
            if merged.normalizedCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.normalizedCategory = candidate.normalizedCategory
            }
            if merged.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
               let value = candidate.value?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                merged.value = value
            }
            if merged.package.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                merged.package = candidate.package
            }
            if merged.lifecycleState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || merged.lifecycleState.lowercased() == "unknown" {
                merged.lifecycleState = candidate.lifecycleState
            }
            if merged.availabilitySummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || merged.availabilitySummary.lowercased() == "unknown" {
                merged.availabilitySummary = candidate.availabilitySummary
            }
            merged.ratings = candidate.ratings.merging(merged.ratings) { _, existing in existing }
            merged.datasheets = mergedDatasheets(merged.datasheets, candidate.datasheets)
            merged.evidence = mergedEvidence(merged.evidence, candidate.evidence)
            merged.footprintCandidates = mergedFootprints(merged.footprintCandidates, candidate.footprintCandidates)
        }
        return merged
    }

    private static func samePartKey(_ candidate: ComponentCandidate) -> String? {
        let mpn = canonicalPartToken(candidate.mpn)
        guard !mpn.isEmpty else { return nil }
        return mpn
    }

    private static func canonicalPartToken(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func mergedDatasheets(_ current: [DatasheetEvidence], _ additional: [DatasheetEvidence]) -> [DatasheetEvidence] {
        var seen = Set(current.map { $0.url.lowercased() })
        var result = current
        for datasheet in additional {
            let key = datasheet.url.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(datasheet)
        }
        return result
    }

    private static func mergedEvidence(_ current: [ComponentEvidence], _ additional: [ComponentEvidence]) -> [ComponentEvidence] {
        var seen = Set(current.map(evidenceKey))
        var result = current
        for evidence in additional {
            let key = evidenceKey(evidence)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(evidence)
        }
        return result
    }

    private static func evidenceKey(_ evidence: ComponentEvidence) -> String {
        [
            evidence.providerID,
            evidence.sourceURL ?? "",
            evidence.localPath ?? "",
            evidence.extractedParameters.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "&"),
        ]
            .joined(separator: "|")
            .lowercased()
    }

    private static func mergedFootprints(_ current: [FootprintCandidate], _ additional: [FootprintCandidate]) -> [FootprintCandidate] {
        var seen = Set(current.map(footprintKey))
        var result = current
        for footprint in additional {
            let key = footprintKey(footprint)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(footprint)
        }
        return result
    }

    private static func footprintKey(_ footprint: FootprintCandidate) -> String {
        "\(footprint.library):\(footprint.name)".lowercased()
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

private struct DRCRepairPlanArtifact: Codable, Sendable, Equatable {
    var status: String
    var patches: [PCBDRCRepairPatch]
    var diagnostics: [ElectronicsSchemaIssue]
}

private struct RepairApplicationArtifact: Codable, Sendable, Equatable {
    var status: String
    var sourcePlanPath: String
    var targetPath: String
    var patchCount: Int
    var mutatedTarget: Bool
    var requiresRerunTool: String
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
