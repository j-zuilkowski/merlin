import Foundation

struct ToolbarAction: Identifiable, Codable, Sendable {
    var id: UUID
    var label: String
    var command: String
    var shortcut: String?

    func run() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", command]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: ToolbarActionError.nonZeroExit(Int(process.terminationStatus), output))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

enum ToolbarActionError: Error, LocalizedError {
    case nonZeroExit(Int, String)

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let code, let output):
            return "Command exited \(code): \(output.prefix(200))"
        }
    }
}
