import Foundation

enum DisciplineCLI {

    static func run(arguments: [String]) async -> Int32 {
        guard arguments.count >= 3 else {
            printUsage()
            return 2
        }

        let subcommand = arguments[1]
        let projectPath = arguments[2]

        switch subcommand {
        case "post-commit":
            return await runPostCommit(projectPath: projectPath)
        case "pre-push":
            return await runPrePush(projectPath: projectPath)
        default:
            printUsage()
            return 2
        }
    }

    private static func runPostCommit(projectPath: String) async -> Int32 {
        print("merlin-discipline: post-commit \(projectPath)")
        let log = eventLog(projectPath: projectPath)
        let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: projectPath)
        let whyResult = await WHYCommentGate().check(projectPath: projectPath, adapter: adapter)
        switch whyResult {
        case .pass:
            print("merlin-discipline: WHY comment gate passed")
            await record(
                log: log,
                subcommand: "post-commit",
                step: "why-comment-gate",
                detail: "WHY comment gate passed",
                passed: true
            )
            await record(
                log: log,
                subcommand: "post-commit",
                step: "result",
                detail: "post-commit passed",
                passed: true
            )
            return 0
        case .block(let violations):
            printWHYViolations(violations)
            await record(
                log: log,
                subcommand: "post-commit",
                step: "why-comment-gate",
                detail: "\(violations.count) WHY comment violation(s)",
                passed: false
            )
            await record(
                log: log,
                subcommand: "post-commit",
                step: "result",
                detail: "post-commit blocked",
                passed: false
            )
            return 1
        }
    }

    private static func runPrePush(projectPath: String) async -> Int32 {
        print("merlin-discipline: pre-push \(projectPath)")
        let log = eventLog(projectPath: projectPath)
        let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: projectPath)

        let whyResult = await WHYCommentGate().check(projectPath: projectPath, adapter: adapter)
        let changedDocs = changedMarkdownDocs(projectPath: projectPath)
        let proseResult = await ProseGate().check(changedDocFiles: changedDocs, adapter: adapter)

        var shouldBlock = false
        switch whyResult {
        case .pass:
            print("merlin-discipline: WHY comment gate passed")
            await record(
                log: log,
                subcommand: "pre-push",
                step: "why-comment-gate",
                detail: "WHY comment gate passed",
                passed: true
            )
        case .block(let violations):
            printWHYViolations(violations)
            await record(
                log: log,
                subcommand: "pre-push",
                step: "why-comment-gate",
                detail: "\(violations.count) WHY comment violation(s)",
                passed: false
            )
            shouldBlock = true
        }

        switch proseResult {
        case .pass:
            print("merlin-discipline: prose gate passed")
            await record(
                log: log,
                subcommand: "pre-push",
                step: "prose-gate",
                detail: "prose gate passed for \(changedDocs.count) changed doc(s)",
                passed: true
            )
        case .block(let findings):
            printProseFindings(findings)
            await record(
                log: log,
                subcommand: "pre-push",
                step: "prose-gate",
                detail: "\(findings.count) prose readability violation(s)",
                passed: false
            )
            shouldBlock = true
        }

        await record(
            log: log,
            subcommand: "pre-push",
            step: "result",
            detail: shouldBlock ? "pre-push blocked" : "pre-push passed",
            passed: !shouldBlock
        )
        return shouldBlock ? 1 : 0
    }

    private static func eventLog(projectPath: String) -> DisciplineEventLog {
        let path = URL(fileURLWithPath: projectPath, isDirectory: true)
            .appendingPathComponent(".merlin/discipline-events.jsonl")
            .path
        return DisciplineEventLog(logPath: path)
    }

    private static func record(
        log: DisciplineEventLog,
        subcommand: String,
        step: String,
        detail: String,
        passed: Bool?
    ) async {
        try? await log.record(DisciplineEvent(
            timestamp: Date(),
            subcommand: subcommand,
            step: step,
            detail: detail,
            passed: passed
        ))
    }

    private static func changedMarkdownDocs(projectPath: String) -> [String] {
        if let diffDocs = markdownDocsFromGitDiff(projectPath: projectPath) {
            return diffDocs
        }
        return enumerateMarkdownDocs(projectPath: projectPath)
    }

    private static func markdownDocsFromGitDiff(projectPath: String) -> [String]? {
        let result = runProcess(
            executable: "/usr/bin/env",
            arguments: ["git", "-C", projectPath, "diff", "--name-only", "@{upstream}", "--", "*.md"]
        )
        guard result.status == 0 else { return nil }

        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        return result.output
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.isEmpty }
            .map { root.appendingPathComponent($0).standardizedFileURL.path }
            .filter { FileManager.default.fileExists(atPath: $0) }
            .sorted()
    }

    private static func enumerateMarkdownDocs(projectPath: String) -> [String] {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var docs: [String] = []
        for case let url as URL in enumerator where url.pathExtension == "md" {
            docs.append(url.path)
        }
        return docs.sorted()
    }

    private static func printWHYViolations(_ violations: [WhyCommentTrigger]) {
        for violation in violations {
            print("merlin-discipline: WHY violation \(violation.file):\(violation.line) \(violation.reason)")
        }
    }

    private static func printProseFindings(_ findings: [ReadabilityFinding]) {
        for finding in findings {
            let name = URL(fileURLWithPath: finding.docFile).lastPathComponent
            let message = String(
                format: "merlin-discipline: prose violation %@ grade %.1f exceeds target %.1f",
                name,
                finding.measuredGrade,
                finding.targetGrade
            )
            print(message)
        }
    }

    private static func printUsage() {
        writeStderr("usage: merlin-discipline <post-commit|pre-push> <project-path>\n")
    }

    private static func writeStderr(_ message: String) {
        guard let data = message.data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }

    private static func runProcess(executable: String, arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (127, "")
        }
    }
}

#if MERLIN_DISCIPLINE_CLI
actor ToolRequirementCoordinator {
    static let shared = ToolRequirementCoordinator()

    func ensure(_ id: String) async -> Bool {
        let executable = executableName(for: id)
        return Self.runProcess(executable: "/usr/bin/which", arguments: [executable]) == 0 ||
            candidatePaths(for: executable).contains {
                FileManager.default.isExecutableFile(atPath: $0)
            }
    }

    private func executableName(for id: String) -> String {
        switch id {
        case "python":
            return "python3"
        default:
            return id
        }
    }

    private func candidatePaths(for executable: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(home)/.cargo/bin",
            "\(home)/.lmstudio/bin"
        ].map { "\($0)/\(executable)" }
    }

    private static func runProcess(executable: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 127
        }
    }
}
#endif
