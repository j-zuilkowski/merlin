import Foundation

struct XcresultSummary {
    var testFailures: [TestFailure]?
    var warnings: [String]
    var coverage: Double?

    struct TestFailure {
        var testName: String
        var message: String
        var file: String?
        var line: Int?
    }
}

enum XcodeTools {
    static var derivedDataPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
            .path
    }

    static func build(scheme: String, configuration: String, destination: String?) async throws -> ShellResult {
        try await runXcodebuild(
            ["-scheme", scheme, "build", "-configuration", configuration] + destinationArguments(destination),
            timeoutSeconds: 600
        )
    }

    static func test(scheme: String, testID: String?) async throws -> ShellResult {
        var args = ["-scheme", scheme, "test"]
        if let testID {
            args += ["-only-testing:\(testID)"]
        }
        return try await runXcodebuild(args, timeoutSeconds: 600)
    }

    static func clean() async throws -> ShellResult {
        try await runXcodebuild(["clean"], timeoutSeconds: 600)
    }

    static func cleanDerivedData() async throws {
        let path = URL(fileURLWithPath: derivedDataPath)
        if FileManager.default.fileExists(atPath: path.path) {
            try FileManager.default.removeItem(at: path)
        }
    }

    static func parseXcresult(path: String) throws -> XcresultSummary {
        guard FileManager.default.fileExists(atPath: path) else {
            return XcresultSummary(testFailures: [], warnings: [], coverage: nil)
        }

        let command = "xcrun xcresulttool get --path \(shellQuote(path)) --format json"
        let output = try runSync(command: command)
        let data = Data(output.utf8)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let failures = extractFailures(from: json)
        let warnings = extractWarnings(from: json)
        let coverage = extractCoverage(from: json)
        return XcresultSummary(testFailures: failures ?? [], warnings: warnings, coverage: coverage)
    }

    static func openFile(path: String, line: Int) async throws {
        let script = openFileAppleScript(path: path, line: line)
        _ = try await ShellTool.run(command: "osascript -e \(shellQuote(script))", cwd: nil, timeoutSeconds: 30)
    }

    static func openFileAppleScript(path: String, line: Int) -> String {
        """
        tell application "Xcode"
            open POSIX file "\(path)"
            activate
            tell application "System Events"
                keystroke "l" using command down
                keystroke "\(line)"
                key code 36
            end tell
        end tell
        """
    }

    static func simulatorList() async throws -> String {
        let result = try await ShellTool.run(command: "xcrun simctl list --json", cwd: nil, timeoutSeconds: 120)
        return result.stdout
    }

    static func simulatorBoot(udid: String) async throws {
        _ = try await ShellTool.run(command: "xcrun simctl boot \(shellQuote(udid))", cwd: nil, timeoutSeconds: 120)
    }

    static func simulatorScreenshot(udid: String) async throws -> Data {
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: temp) }
        _ = try await ShellTool.run(
            command: "xcrun simctl io \(shellQuote(udid)) screenshot --type=png \(shellQuote(temp.path))",
            cwd: nil,
            timeoutSeconds: 120
        )
        return try Data(contentsOf: temp)
    }

    static func simulatorInstall(udid: String, appPath: String) async throws {
        _ = try await ShellTool.run(
            command: "xcrun simctl install \(shellQuote(udid)) \(shellQuote(appPath))",
            cwd: nil,
            timeoutSeconds: 120
        )
    }

    static func spmResolve(cwd: String) async throws -> ShellResult {
        try await ShellTool.run(command: "swift package resolve", cwd: cwd, timeoutSeconds: 600)
    }

    static func spmList(cwd: String) async throws -> ShellResult {
        try await ShellTool.run(command: "swift package show-dependencies", cwd: cwd, timeoutSeconds: 600)
    }

    private static func runXcodebuild(_ args: [String], timeoutSeconds: Int) async throws -> ShellResult {
        let command = (["xcodebuild"] + args + ["-derivedDataPath", shellQuote(derivedDataPath)]).joined(separator: " ")
        return try await ShellTool.run(command: command, cwd: FileManager.default.currentDirectoryPath, timeoutSeconds: timeoutSeconds)
    }

    private static func destinationArguments(_ destination: String?) -> [String] {
        guard let destination else { return ["-destination", "platform=macOS"] }
        return ["-destination", destination]
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func runSync(command: String) throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }

    private static func extractFailures(from json: [String: Any]?) -> [XcresultSummary.TestFailure]? {
        guard let json else { return nil }
        if let failures = json["testFailures"] as? [[String: Any]] {
            return failures.map { item in
                XcresultSummary.TestFailure(
                    testName: item["testName"] as? String ?? "",
                    message: item["message"] as? String ?? "",
                    file: item["file"] as? String,
                    line: item["line"] as? Int
                )
            }
        }
        return []
    }

    private static func extractWarnings(from json: [String: Any]?) -> [String] {
        guard let json else { return [] }
        if let warnings = json["warnings"] as? [String] {
            return warnings
        }
        return []
    }

    private static func extractCoverage(from json: [String: Any]?) -> Double? {
        guard let json else { return nil }
        if let coverage = json["coverage"] as? Double {
            return coverage
        }
        if let coverage = json["coverage"] as? NSNumber {
            return coverage.doubleValue
        }
        return nil
    }
}
