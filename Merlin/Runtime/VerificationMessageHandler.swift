import Foundation

struct VerificationMessageHandler: WorkspaceMessageHandler {
    var backend: any VerificationBackend

    func handle(_ request: WorkspaceMessageRequest, context: WorkspaceHandlerContext) async -> WorkspaceMessageResponse {
        guard request.origin.permissionScope.allows(.readOnly) else {
            return .unauthorized(requestID: request.id, message: "verification origin is not authorized")
        }

        let taskType = DomainTaskType(
            domainID: request.address.namespace.replacingOccurrences(of: "domain.", with: ""),
            name: "verification",
            displayName: "Verification"
        )
        guard let commands = await backend.verificationCommands(for: taskType), commands.isEmpty == false else {
            return .blocked(
                requestID: request.id,
                code: "NO_VERIFICATION_COMMANDS",
                message: "No deterministic verification commands are registered for this task."
            )
        }

        for command in commands {
            do {
                let result = try await ShellTool.run(command: command.command, cwd: context.workspaceRoot.path, timeoutSeconds: 120)
                switch command.passCondition {
                case .exitCode(let expected):
                    guard result.exitCode == expected else {
                        return .failed(
                            requestID: request.id,
                            code: "VERIFICATION_FAILED",
                            message: "\(command.label) exited \(result.exitCode), expected \(expected)."
                        )
                    }
                case .outputContains(let text):
                    guard result.stdout.contains(text) || result.stderr.contains(text) else {
                        return .failed(
                            requestID: request.id,
                            code: "VERIFICATION_FAILED",
                            message: "\(command.label) output did not contain \(text)."
                        )
                    }
                case .custom(let predicate):
                    guard predicate(result.stdout + result.stderr) else {
                        return .failed(
                            requestID: request.id,
                            code: "VERIFICATION_FAILED",
                            message: "\(command.label) custom pass condition failed."
                        )
                    }
                }
            } catch {
                return .failed(
                    requestID: request.id,
                    code: "VERIFICATION_ERROR",
                    message: String(describing: error)
                )
            }
        }

        return .ok(requestID: request.id, payload: .jsonString(#"{"status":"passed"}"#))
    }
}
