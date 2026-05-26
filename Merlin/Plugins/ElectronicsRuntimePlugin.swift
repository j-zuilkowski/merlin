import Foundation

struct ElectronicsRuntimePlugin {
    let metadata: RuntimePluginMetadata

    init() {
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
                ElectronicsCapabilityHandler(capability: capability),
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

    func handle(_ request: WorkspaceMessageRequest, context: WorkspaceHandlerContext) async -> WorkspaceMessageResponse {
        guard request.origin.permissionScope.allows(capability.requiredPermissionScope) else {
            return .unauthorized(requestID: request.id, message: "electronics capability requires \(capability.requiredPermissionScope.rawValue)")
        }

        if request.address.capability == "kicad_route_pass" {
            await context.bus.publish(WorkspaceMessageEvent(
                id: UUID(),
                requestID: request.id,
                address: request.address,
                origin: request.origin,
                kind: .progress,
                payload: .jsonString(#"{"step":"routing"}"#)
            ))
            let artifact = WorkspaceArtifactRef(
                id: "route-\(request.id.uuidString)",
                kind: "routing_report",
                url: context.workspaceRoot.appendingPathComponent(".merlin/electronics/routing-report.json"),
                displayName: "Routing Report",
                metadata: ["capability": request.address.capability]
            )
            await context.bus.publish(WorkspaceMessageEvent(
                id: UUID(),
                requestID: request.id,
                address: request.address,
                origin: request.origin,
                kind: .artifactProduced,
                payload: try? .encodeJSON(artifact)
            ))
            return .ok(
                requestID: request.id,
                payload: .jsonString(#"{"status":"COMPLETE"}"#),
                artifacts: [artifact]
            )
        }

        return .ok(requestID: request.id, payload: .jsonString(#"{"status":"COMPLETE"}"#))
    }
}
