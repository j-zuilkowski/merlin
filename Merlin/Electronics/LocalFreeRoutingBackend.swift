import Foundation

struct LocalFreeRoutingHealth: Codable, Sendable, Equatable {
    var status: KiCadStatus
    var blockedReason: ElectronicsBlockedReason?
    var executableURL: URL
}

struct LocalFreeRoutingRequest: Codable, Sendable, Equatable {
    var jobID: String
    var boardURL: URL
    var dsnURL: URL
    var sesURL: URL
    var logURL: URL
    var maxIterations: Int
}

struct FreeRoutingProcessResult: Codable, Sendable, Equatable {
    var exitCode: Int32
    var stdout: String
    var stderr: String
}

protocol FreeRoutingProcessRunning: Sendable {
    func run(executableURL: URL, arguments: [String], timeoutSeconds: Int) async -> FreeRoutingProcessResult
}

struct SystemFreeRoutingProcessRunner: FreeRoutingProcessRunning {
    func run(executableURL: URL, arguments: [String], timeoutSeconds: Int) async -> FreeRoutingProcessResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                continuation.resume(returning: FreeRoutingProcessResult(
                    exitCode: 127,
                    stdout: "",
                    stderr: error.localizedDescription
                ))
                return
            }

            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if process.isRunning {
                    process.terminate()
                }
            }

            process.waitUntilExit()
            timeoutTask.cancel()

            let stdoutText = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderrText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            continuation.resume(returning: FreeRoutingProcessResult(
                exitCode: process.terminationStatus,
                stdout: stdoutText,
                stderr: stderrText
            ))
        }
    }
}

struct LocalFreeRoutingBackend: Sendable {
    var executableURL: URL
    var timeoutSeconds: Int
    var routingBackend: ElectronicsRoutingBackend { .localFreeRouting }

    private let fileExists: @Sendable (URL) -> Bool
    private let runner: any FreeRoutingProcessRunning

    init(
        executableURL: URL = URL(fileURLWithPath: "/Applications/freerouting.app/Contents/MacOS/freerouting"),
        timeoutSeconds: Int = FreeRoutingProfile.default.timeoutSeconds,
        fileExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        runner: any FreeRoutingProcessRunning = SystemFreeRoutingProcessRunner()
    ) {
        self.executableURL = executableURL
        self.timeoutSeconds = timeoutSeconds
        self.fileExists = fileExists
        self.runner = runner
    }

    func health() async -> LocalFreeRoutingHealth {
        guard fileExists(executableURL) else {
            return LocalFreeRoutingHealth(
                status: .blockedTooling,
                blockedReason: .missingFreeRouting,
                executableURL: executableURL
            )
        }
        return LocalFreeRoutingHealth(status: .complete, blockedReason: nil, executableURL: executableURL)
    }

    func route(
        _ request: LocalFreeRoutingRequest,
        bus: WorkspaceMessageBus,
        origin: WorkspaceMessageOrigin
    ) async -> KiCadToolResult {
        let routeAddress = WorkspaceMessageAddress(namespace: "plugin.electronics", capability: "kicad_route_pass")
        let requestID = UUID()

        let health = await health()
        guard health.status == .complete else {
            await publishDiagnostic(
                reason: health.blockedReason ?? .missingFreeRouting,
                requestID: requestID,
                address: routeAddress,
                bus: bus,
                origin: origin
            )
            return KiCadToolResult(
                status: .blockedTooling,
                warnings: [KiCadWarning(
                    code: health.blockedReason?.rawValue ?? ElectronicsBlockedReason.missingFreeRouting.rawValue,
                    message: "Local FreeRouting executable is unavailable at \(executableURL.path).",
                    affectedRefs: [executableURL.path],
                    suggestedAction: "Install FreeRouting at /Applications/freerouting.app or configure the local backend path."
                )]
            )
        }

        await bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: requestID,
            address: routeAddress,
            origin: origin,
            kind: .progress,
            payload: .jsonString(#"{"step":"freerouting_start"}"#)
        ))

        let arguments = [
            "-de", request.dsnURL.path,
            "-do", request.sesURL.path,
            "-mp", "\(request.maxIterations)",
        ]
        let process = await runner.run(
            executableURL: executableURL,
            arguments: arguments,
            timeoutSeconds: timeoutSeconds
        )

        try? FileManager.default.createDirectory(
            at: request.logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? "\(process.stdout)\n\(process.stderr)".write(to: request.logURL, atomically: true, encoding: .utf8)

        guard process.exitCode == 0 else {
            await publishDiagnostic(
                reason: .routeFailed,
                requestID: requestID,
                address: routeAddress,
                bus: bus,
                origin: origin
            )
            return KiCadToolResult(
                status: .blocked,
                warnings: [KiCadWarning(
                    code: ElectronicsBlockedReason.routeFailed.rawValue,
                    message: "FreeRouting exited with status \(process.exitCode).",
                    affectedRefs: [request.dsnURL.path],
                    suggestedAction: "Inspect the route log and repair placement, constraints, or net classes."
                )]
            )
        }

        let artifacts = [
            ArtifactRef(path: request.dsnURL.path, kind: ElectronicsArtifactKind.routingInterchange.rawValue),
            ArtifactRef(path: request.sesURL.path, kind: ElectronicsArtifactKind.routingResult.rawValue),
            ArtifactRef(path: request.logURL.path, kind: "route_log"),
        ]
        for artifact in artifacts {
            await bus.publish(WorkspaceMessageEvent(
                id: UUID(),
                requestID: requestID,
                address: routeAddress,
                origin: origin,
                kind: .artifactProduced,
                payload: try? .encodeJSON(WorkspaceArtifactRef(
                    id: "\(request.jobID)-\(artifact.kind)",
                    kind: artifact.kind,
                    url: URL(fileURLWithPath: artifact.path),
                    displayName: artifact.kind,
                    metadata: ["job_id": request.jobID]
                ))
            ))
        }

        await bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: requestID,
            address: routeAddress,
            origin: origin,
            kind: .progress,
            payload: .jsonString(#"{"step":"freerouting_complete"}"#)
        ))

        return KiCadToolResult(
            status: .complete,
            artifacts: artifacts,
            metrics: ["exit_code": Double(process.exitCode)]
        )
    }

    private func publishDiagnostic(
        reason: ElectronicsBlockedReason,
        requestID: UUID,
        address: WorkspaceMessageAddress,
        bus: WorkspaceMessageBus,
        origin: WorkspaceMessageOrigin
    ) async {
        await bus.publish(WorkspaceMessageEvent(
            id: UUID(),
            requestID: requestID,
            address: address,
            origin: origin,
            kind: .diagnostic,
            payload: .jsonString(#"{"code":"\#(reason.rawValue)"}"#)
        ))
    }
}
