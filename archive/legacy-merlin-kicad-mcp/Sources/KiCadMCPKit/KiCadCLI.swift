import Foundation

/// Locates and runs `kicad-cli` (KiCad 10's command-line tool). On macOS the binary
/// ships inside the app bundle and is not on `PATH`.
enum KiCadCLI {

    /// The standard macOS app-bundle location for `kicad-cli`.
    static let bundledPath = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"

    struct RunResult: Sendable {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        var ok: Bool { exitCode == 0 }
    }

    /// Resolves a usable `kicad-cli` path: the app bundle first, then `PATH`.
    static func resolvePath() -> String? {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: bundledPath) { return bundledPath }
        let which = run("/usr/bin/which", ["kicad-cli"])
        let trimmed = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.isEmpty || !fm.isExecutableFile(atPath: trimmed)) ? nil : trimmed
    }

    /// Runs an arbitrary executable, capturing stdout/stderr.
    @discardableResult
    static func run(_ launchPath: String, _ args: [String], cwd: String? = nil) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        do {
            try process.run()
        } catch {
            return RunResult(stdout: "", stderr: "launch failed: \(error.localizedDescription)",
                             exitCode: -1)
        }
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return RunResult(
            stdout: String(data: outData, encoding: .utf8) ?? "",
            stderr: String(data: errData, encoding: .utf8) ?? "",
            exitCode: process.terminationStatus
        )
    }

    /// Runs `kicad-cli` with `args`. Returns nil when `kicad-cli` cannot be located.
    static func cli(_ args: [String], cwd: String? = nil) -> RunResult? {
        guard let path = resolvePath() else { return nil }
        return run(path, args, cwd: cwd)
    }

    /// Parses the major version from `kicad-cli version` output (e.g. "9.0.1" → 9).
    static func majorVersion(from output: String) -> Int? {
        let digits = output.unicodeScalars
            .split(whereSeparator: { !CharacterSet.decimalDigits.contains($0) })
            .first
        guard let digits else { return nil }
        return Int(String(String.UnicodeScalarView(digits)))
    }
}
