import Foundation

struct ElectronicsRuntimePlugin {
    let metadata: RuntimePluginMetadata
    private let tooling: ElectronicsToolingState
    private let routeBackend: any ElectronicsRoutePassRunning

    init(
        tooling: ElectronicsToolingState = .available,
        routeBackend: any ElectronicsRoutePassRunning = LocalFreeRoutingBackend()
    ) {
        self.tooling = tooling
        self.routeBackend = routeBackend
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
            settingsSchema: ElectronicsDomain().settingsSchema,
            builtInFactory: "electronics"
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
            payload: .jsonString(#"{"status":"loaded"}"#)
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

        if request.address.capability == "kicad_route_pass" {
            return await handleRoutePass(request, context: context)
        }

        if request.address.capability == "kicad_submit_vendor_order" {
            return await blockForApproval(request, context: context)
        }

        return block(
            request,
            reason: .missingProjectFile,
            message: "Electronics capability \(request.address.capability) requires a valid KiCad project payload and cannot complete without evidence.",
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

    private func handleRoutePass(
        _ request: WorkspaceMessageRequest,
        context: WorkspaceHandlerContext
    ) async -> WorkspaceMessageResponse {
        guard let payload = try? request.payload.decodeJSON(ElectronicsRoutePassRequestPayload.self),
              let routeRequest = payload.localRequest else {
            return block(
                request,
                reason: .missingProjectFile,
                message: "Route pass requires job_id, board_path, dsn_path, ses_path, and log_path.",
                context: context
            )
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
        return .blocked(
            requestID: request.id,
            code: "APPROVAL_REQUIRED",
            message: "Vendor order submission requires explicit user approval."
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

private extension WorkspaceMessagePayload {
    func jsonObject() -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
