import Foundation

struct WorkspaceMessageAddress: Hashable, Codable, Sendable, Equatable, CustomStringConvertible {
    var namespace: String
    var capability: String

    var description: String {
        "\(namespace)/\(capability)"
    }
}

enum WorkspacePermissionScope: String, Codable, Sendable, CaseIterable {
    case readOnly
    case workspaceWrite
    case worktreeWrite
    case externalSideEffect
    case userApprovedIrreversible

    func allows(_ required: WorkspacePermissionScope) -> Bool {
        switch required {
        case .readOnly:
            return true
        case .worktreeWrite:
            return self == .worktreeWrite || self == .workspaceWrite || self == .userApprovedIrreversible
        case .workspaceWrite:
            return self == .workspaceWrite || self == .userApprovedIrreversible
        case .externalSideEffect:
            return self == .externalSideEffect || self == .userApprovedIrreversible
        case .userApprovedIrreversible:
            return self == .userApprovedIrreversible
        }
    }
}

struct WorkspaceMessageOrigin: Codable, Sendable, Equatable {
    var workspaceID: String
    var sessionID: UUID?
    var agentID: UUID?
    var subagentID: UUID?
    var worktreeID: String?
    var subagentDepth: Int
    var permissionScope: WorkspacePermissionScope
    var activeDomainIDs: [String]
}

struct WorkspaceMessagePayload: Codable, Sendable, Equatable {
    var contentType: String
    var data: Data

    init(contentType: String = "application/json", data: Data = Data()) {
        self.contentType = contentType
        self.data = data
    }

    static let empty = WorkspaceMessagePayload()

    static func jsonString(_ string: String) -> WorkspaceMessagePayload {
        WorkspaceMessagePayload(data: Data(string.utf8))
    }

    static func encodeJSON<T: Encodable>(_ value: T) throws -> WorkspaceMessagePayload {
        WorkspaceMessagePayload(data: try WorkspaceJSON.encoder.encode(value))
    }

    func stringValue() -> String {
        String(data: data, encoding: .utf8) ?? ""
    }

    func decodeJSON<T: Decodable>(_ type: T.Type) throws -> T {
        try WorkspaceJSON.decoder.decode(type, from: data)
    }
}

enum WorkspaceMessageResponseStatus: String, Codable, Sendable {
    case ok
    case blocked
    case failed
    case cancelled
    case timedOut
    case unauthorized
}

struct WorkspaceDiagnostic: Codable, Sendable, Equatable {
    var code: String
    var message: String
    var severity: String
}

struct WorkspaceArtifactRef: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var kind: String
    var url: URL
    var displayName: String?
    var metadata: [String: String]
}

struct WorkspaceMessageRequest: Codable, Sendable, Equatable {
    var id: UUID
    var address: WorkspaceMessageAddress
    var origin: WorkspaceMessageOrigin
    var payload: WorkspaceMessagePayload
    var cancellationGroup: String?
}

struct WorkspaceMessageResponse: Codable, Sendable, Equatable {
    var requestID: UUID
    var status: WorkspaceMessageResponseStatus
    var payload: WorkspaceMessagePayload?
    var artifacts: [WorkspaceArtifactRef]
    var diagnostics: [WorkspaceDiagnostic]

    static func ok(
        requestID: UUID,
        payload: WorkspaceMessagePayload? = nil,
        artifacts: [WorkspaceArtifactRef] = [],
        diagnostics: [WorkspaceDiagnostic] = []
    ) -> WorkspaceMessageResponse {
        WorkspaceMessageResponse(
            requestID: requestID,
            status: .ok,
            payload: payload,
            artifacts: artifacts,
            diagnostics: diagnostics
        )
    }

    static func failed(requestID: UUID, code: String, message: String) -> WorkspaceMessageResponse {
        diagnostic(requestID: requestID, status: .failed, code: code, message: message)
    }

    static func blocked(requestID: UUID, code: String, message: String) -> WorkspaceMessageResponse {
        diagnostic(requestID: requestID, status: .blocked, code: code, message: message)
    }

    static func unauthorized(
        requestID: UUID,
        code: String = "UNAUTHORIZED_SCOPE",
        message: String
    ) -> WorkspaceMessageResponse {
        diagnostic(requestID: requestID, status: .unauthorized, code: code, message: message)
    }

    static func timedOut(requestID: UUID) -> WorkspaceMessageResponse {
        diagnostic(
            requestID: requestID,
            status: .timedOut,
            code: "REQUEST_TIMED_OUT",
            message: "Workspace message request timed out."
        )
    }

    static func cancelled(requestID: UUID) -> WorkspaceMessageResponse {
        diagnostic(
            requestID: requestID,
            status: .cancelled,
            code: "REQUEST_CANCELLED",
            message: "Workspace message request was cancelled."
        )
    }

    private static func diagnostic(
        requestID: UUID,
        status: WorkspaceMessageResponseStatus,
        code: String,
        message: String
    ) -> WorkspaceMessageResponse {
        WorkspaceMessageResponse(
            requestID: requestID,
            status: status,
            payload: nil,
            artifacts: [],
            diagnostics: [WorkspaceDiagnostic(code: code, message: message, severity: "error")]
        )
    }
}

enum WorkspaceMessageEventKind: String, Codable, Sendable, CaseIterable {
    case progress
    case artifactProduced
    case healthChanged
    case diagnostic
    case approvalRequired
    case settingsChanged
    case settingsValidation
}

struct WorkspaceMessageEvent: Codable, Sendable, Equatable, Identifiable {
    var id: UUID
    var requestID: UUID?
    var address: WorkspaceMessageAddress
    var origin: WorkspaceMessageOrigin?
    var kind: WorkspaceMessageEventKind
    var payload: WorkspaceMessagePayload?
}

struct WorkspaceMessageEventFilter: Sendable, Equatable {
    var requestID: UUID? = nil
    var namespacePrefix: String? = nil
    var address: WorkspaceMessageAddress? = nil

    func matches(_ event: WorkspaceMessageEvent) -> Bool {
        if let requestID, event.requestID != requestID {
            return false
        }
        if let address, event.address != address {
            return false
        }
        if let namespacePrefix, event.address.namespace.hasPrefix(namespacePrefix) == false {
            return false
        }
        return true
    }
}

enum WorkspaceCapabilityKind: String, Codable, Sendable {
    case tool
    case verification
    case settings
    case artifactProvider
    case workflow
}

struct WorkspaceCapability: Codable, Sendable, Equatable {
    var id: String
    var displayName: String
    var kind: WorkspaceCapabilityKind
    var address: WorkspaceMessageAddress
    var requiredPermissionScope: WorkspacePermissionScope
}

struct WorkspaceSettingsSchema: Codable, Sendable, Equatable {
    var namespace: String
    var title: String
    var fields: [WorkspaceSettingsField]
}

struct WorkspaceSettingsField: Codable, Sendable, Equatable {
    var key: String
    var label: String
    var kind: WorkspaceSettingsFieldKind
    var defaultValue: WorkspaceSettingsValue?
    var isSecret: Bool
    var help: String?
}

enum WorkspaceSettingsFieldKind: String, Codable, Sendable {
    case string
    case integer
    case double
    case boolean
    case path
    case secret
}

enum WorkspaceSettingsValue: Codable, Sendable, Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
}

struct WorkspaceSettingsNamespace: Codable, Sendable, Equatable {
    var namespace: String
    var values: [String: WorkspaceSettingsValue]
}

struct ToolRoute: Sendable, Equatable {
    var toolName: String
    var address: WorkspaceMessageAddress
    var timeout: Duration
    var requiredPermissionScope: WorkspacePermissionScope
}

struct WorkspaceBootstrapMetadata: Codable, Sendable, Equatable {
    var apiVersion: String
    var workspaceID: String
    var rootPath: String
    var capabilities: [WorkspaceCapability]
    var settingsSchemas: [WorkspaceSettingsSchema]
}

struct WorkspaceHandlerContext: Sendable {
    var bus: WorkspaceMessageBus
    var workspaceRoot: URL
    var settings: WorkspaceSettingsNamespace
}

protocol WorkspaceMessageHandler: Sendable {
    func handle(_ request: WorkspaceMessageRequest, context: WorkspaceHandlerContext) async -> WorkspaceMessageResponse
}

enum WorkspaceJSON {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
