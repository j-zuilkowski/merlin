import Foundation

struct KiCadMCPServerConfig: Codable, Sendable, Equatable {
    var serverPath: String
    var kicadCLIPath: String
    var freeRoutingPath: String
    var requiredToolNames: [String]
}

struct KiCadMCPToolingStatus: Codable, Sendable, Equatable {
    var serverAvailable: Bool
    var availableToolNames: [String]
    var kicadVersionOutput: String

    static let unavailable = KiCadMCPToolingStatus(
        serverAvailable: false,
        availableToolNames: [],
        kicadVersionOutput: ""
    )

    static func available(tools: [String], versionOutput: String = "KiCad Version: 10.0.0") -> KiCadMCPToolingStatus {
        KiCadMCPToolingStatus(
            serverAvailable: true,
            availableToolNames: tools,
            kicadVersionOutput: versionOutput
        )
    }
}

struct KiCadVersionDecision: Codable, Sendable, Equatable {
    var status: KiCadStatus
    var detectedMajorVersion: Int?
    var code: String
    var message: String
}

enum KiCadVersionGate {
    static func parseMajorVersion(from output: String) -> Int? {
        let digits = output.unicodeScalars
            .map { Character($0) }
            .split(whereSeparator: { !$0.isNumber })
            .first
        guard let digits else { return nil }
        return Int(String(digits))
    }

    static func evaluate(versionOutput: String, requiredMajor: Int) -> KiCadVersionDecision {
        guard let major = parseMajorVersion(from: versionOutput) else {
            return KiCadVersionDecision(
                status: .blockedVersion,
                detectedMajorVersion: nil,
                code: "KICAD_VERSION_PARSE_FAILED",
                message: "Unable to parse KiCad CLI major version from output."
            )
        }

        guard major >= requiredMajor else {
            return KiCadVersionDecision(
                status: .blockedVersion,
                detectedMajorVersion: major,
                code: "KICAD_VERSION_UNSUPPORTED",
                message: "KiCad major version \(major) is below required \(requiredMajor)."
            )
        }

        return KiCadVersionDecision(
            status: .complete,
            detectedMajorVersion: major,
            code: "KICAD_VERSION_SUPPORTED",
            message: "KiCad version gate passed."
        )
    }
}

@MainActor
protocol KiCadToolExecutor {
    func execute(toolName: String, arguments: [String: Any]) async throws -> KiCadToolResult
    func execute(toolName: String, argumentsJSON: String) async throws -> KiCadToolResult
}

extension KiCadToolExecutor {
    func execute(toolName: String, argumentsJSON: String) async throws -> KiCadToolResult {
        let arguments = Self.decodeArguments(from: argumentsJSON)
        return try await execute(toolName: toolName, arguments: arguments)
    }

    private static func decodeArguments(from json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }
}

@MainActor
struct KiCadMCPToolExecutor: KiCadToolExecutor {
    var config: KiCadMCPServerConfig
    var probe: KiCadMCPToolingStatus
    var requiredMajorVersion: Int
    private let client: any KiCadMCPClient

    init(config: KiCadMCPServerConfig,
         probe: KiCadMCPToolingStatus,
         client: (any KiCadMCPClient)? = nil,
         requiredMajorVersion: Int = 10) {
        self.config = config
        self.probe = probe
        self.requiredMajorVersion = requiredMajorVersion
        self.client = client ?? KiCadMCPBridgeClient(serverName: config.serverPath)
    }

    func execute(toolName: String, arguments: [String: Any]) async throws -> KiCadToolResult {
        guard probe.serverAvailable else {
            return KiCadToolResult(
                status: .blockedTooling,
                warnings: [KiCadWarning(
                    code: "KICAD_MCP_UNAVAILABLE",
                    message: "KiCad MCP server is unavailable at \(config.serverPath).",
                    affectedRefs: [config.serverPath],
                    suggestedAction: "Start or install the KiCad MCP server."
                )],
                metrics: ["required_major": Double(requiredMajorVersion)]
            )
        }

        let available = Set(probe.availableToolNames)
        let missingRequired = Set(config.requiredToolNames).subtracting(available)
        if !missingRequired.isEmpty {
            return KiCadToolResult(
                status: .blockedTooling,
                warnings: [KiCadWarning(
                    code: "KICAD_MCP_REQUIRED_TOOL_MISSING",
                    message: "Required KiCad MCP tools are missing: \(missingRequired.sorted().joined(separator: ", ")).",
                    affectedRefs: missingRequired.sorted(),
                    suggestedAction: "Install or enable the missing KiCad MCP tools."
                )],
                metrics: ["missing_required_tool_count": Double(missingRequired.count)]
            )
        }

        guard available.contains(toolName) else {
            return KiCadToolResult(
                status: .blockedTooling,
                warnings: [KiCadWarning(
                    code: "KICAD_MCP_TOOL_NOT_AVAILABLE",
                    message: "KiCad MCP tool \(toolName) is not available.",
                    affectedRefs: [toolName],
                    suggestedAction: "Enable \(toolName) in the MCP server."
                )]
            )
        }

        let version = KiCadVersionGate.evaluate(
            versionOutput: probe.kicadVersionOutput,
            requiredMajor: requiredMajorVersion
        )
        guard version.status == .complete else {
            return KiCadToolResult(
                status: .blockedVersion,
                warnings: [KiCadWarning(
                    code: version.code,
                    message: version.message,
                    affectedRefs: [config.kicadCLIPath],
                    suggestedAction: "Install KiCad \(requiredMajorVersion)+ and retry."
                )],
                metrics: ["detected_major": Double(version.detectedMajorVersion ?? 0)]
            )
        }

        do {
            let payload = try await client.execute(toolName: toolName, arguments: arguments)
            return decodeClientResult(payload, toolName: toolName, detectedMajor: version.detectedMajorVersion ?? requiredMajorVersion)
        } catch {
            return blockedToolingResult(
                code: "KICAD_MCP_CLIENT_EXECUTION_FAILED",
                message: "KiCad MCP client failed for \(toolName): \(error.localizedDescription)",
                affectedRefs: [config.serverPath, toolName],
                suggestedAction: "Check the KiCad MCP bridge and retry.",
                metrics: ["detected_major": Double(version.detectedMajorVersion ?? requiredMajorVersion)]
            )
        }
    }

    private func decodeClientResult(_ payload: String, toolName: String, detectedMajor: Int) -> KiCadToolResult {
        guard let data = payload.data(using: .utf8) else {
            return blockedToolingResult(
                code: "KICAD_MCP_RESULT_DECODE_FAILED",
                message: "KiCad MCP client returned non-UTF8 payload for \(toolName).",
                affectedRefs: [config.serverPath, toolName],
                suggestedAction: "Ensure the KiCad MCP server returns JSON-encoded KiCadToolResult values.",
                metrics: ["detected_major": Double(detectedMajor)]
            )
        }

        do {
            let result = try JSONDecoder().decode(KiCadToolResult.self, from: data)
            return result
        } catch {
            return blockedToolingResult(
                code: "KICAD_MCP_RESULT_DECODE_FAILED",
                message: "KiCad MCP client returned an invalid payload for \(toolName): \(error.localizedDescription)",
                affectedRefs: [config.serverPath, toolName],
                suggestedAction: "Ensure the KiCad MCP server returns JSON-encoded KiCadToolResult values.",
                metrics: ["detected_major": Double(detectedMajor)]
            )
        }
    }

    private func blockedToolingResult(
        code: String,
        message: String,
        affectedRefs: [String],
        suggestedAction: String,
        metrics: [String: Double] = [:]
    ) -> KiCadToolResult {
        KiCadToolResult(
            status: .blockedTooling,
            warnings: [
                KiCadWarning(
                    code: code,
                    message: message,
                    affectedRefs: affectedRefs,
                    suggestedAction: suggestedAction
                )
            ],
            metrics: metrics
        )
    }
}
