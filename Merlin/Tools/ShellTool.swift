@preconcurrency import Foundation

struct ShellResult: Sendable {
    var stdout: String
    var stderr: String
    var exitCode: Int32
}

struct ShellOutputLine: Sendable {
    enum Source: Sendable { case stdout, stderr }
    var text: String
    var source: Source
}

enum ShellTool {
    static func stream(command: String, cwd: String?, timeoutSeconds: Int = 120) -> AsyncThrowingStream<ShellOutputLine, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @Sendable in
                do {
                    _ = try await execute(command: command, cwd: cwd, timeoutSeconds: timeoutSeconds) { line in
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    static func run(command: String, cwd: String?, timeoutSeconds: Int = 120) async throws -> ShellResult {
        try await execute(command: command, cwd: cwd, timeoutSeconds: timeoutSeconds) { _ in }
    }

    private static func execute(command: String,
                                cwd: String?,
                                timeoutSeconds: Int,
                                onLine: @escaping @Sendable (ShellOutputLine) -> Void) async throws -> ShellResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if let cwd {
            process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        }

        return try await withTaskCancellationHandler(operation: {
            let timeoutWorkItem = DispatchWorkItem { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(timeoutSeconds), execute: timeoutWorkItem)

            async let stdoutLines = readLines(from: stdoutPipe.fileHandleForReading, source: .stdout, onLine: onLine)
            async let stderrLines = readLines(from: stderrPipe.fileHandleForReading, source: .stderr, onLine: onLine)

            let exitCode = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { p in
                    continuation.resume(returning: p.terminationStatus)
                }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                }
            }

            timeoutWorkItem.cancel()

            let stdout = try await stdoutLines
            let stderr = try await stderrLines
            return normalize(command: command, stdoutLines: stdout, stderrLines: stderr, exitCode: exitCode)
        }, onCancel: {
            process.terminate()
        })
    }

    private static func readLines(from handle: FileHandle,
                                  source: ShellOutputLine.Source,
                                  onLine: @escaping @Sendable (ShellOutputLine) -> Void) async throws -> [String] {
        var lines: [String] = []
        for try await line in handle.bytes.lines {
            lines.append(line)
            onLine(ShellOutputLine(text: line, source: source))
        }
        return lines
    }

    private static func normalize(command: String, stdoutLines: [String], stderrLines: [String], exitCode: Int32) -> ShellResult {
        var stdout = stdoutLines.joined(separator: "\n")
        var stderr = stderrLines.joined(separator: "\n")

        if stdout.isEmpty == false { stdout += "\n" }
        if stderr.isEmpty == false { stderr += "\n" }

        if stderr.isEmpty, command.contains("2>&1"), exitCode != 0, !stdout.isEmpty {
            stderr = stdout
            stdout = ""
        }

        return ShellResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}
