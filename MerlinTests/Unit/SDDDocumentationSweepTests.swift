import XCTest

final class SDDDocumentationSweepTests: XCTestCase {
    private var repoRoot: URL {
        var current = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while current.path != current.deletingLastPathComponent().path {
            if FileManager.default.fileExists(
                atPath: current.appendingPathComponent("project.yml").path
            ) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }

    func testNoStaleSddArtifactReferencesRemain() throws {
        let legacyTasksDir = "pha" + "se" + "s/"
        let legacyTaskPrefix = "pha" + "se-"
        let legacyCommand = "/project:" + "pha" + "se"
        let legacySkill = "project-" + "pha" + "se"
        let forbiddenLiterals: [String] = [
            ["CLAUDE", "md"].joined(separator: "."),
            "CLAUDE" + "MD",
            "claude" + "-md",
            ["architecture", "md"].joined(separator: "."),
            legacyTasksDir,
            legacyTaskPrefix,
            legacyCommand,
            legacySkill
        ]
        let standaloneTask = try NSRegularExpression(
            pattern: #"(?<![A-Za-z])(?i:"# + "pha" + "se" + #")(?![A-Za-z])"#)
        var failures: [String] = []

        for file in try trackedTextFiles() {
            let relative = file.path.replacingOccurrences(of: repoRoot.path + "/", with: "")
            if [
                "MerlinTests/Unit/SDDArtifactCutoverTests.swift",
                "MerlinTests/Unit/ProjectTaskSkillCutoverTests.swift",
                "MerlinTests/Unit/SDDDocumentationSweepTests.swift",
                "tasks/task-344a-sdd-artifact-cutover-tests.md",
                "tasks/task-345a-project-task-skill-tests.md",
                "tasks/task-346a-sdd-doc-sweep-tests.md"
            ].contains(relative) {
                continue
            }
            let text = try String(contentsOf: file, encoding: .utf8)
            for forbidden in forbiddenLiterals where text.contains(forbidden) {
                failures.append("\(relative): contains \(forbidden)")
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if standaloneTask.firstMatch(in: text, range: range) != nil {
                failures.append("\(relative): contains standalone legacy task word")
            }
        }

        XCTAssertTrue(failures.isEmpty, failures.prefix(80).joined(separator: "\n"))
    }

    private func trackedTextFiles() throws -> [URL] {
        let output = try runGit(["ls-files"])
        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.hasPrefix("build/") && !$0.hasPrefix("Merlin.xcodeproj/") }
            .filter { path in
                [
                    "swift", "md", "txt", "toml", "yml", "yaml", "json", "sh",
                    "plist", "template"
                ].contains(URL(fileURLWithPath: path).pathExtension.lowercased())
            }
            .map { repoRoot.appendingPathComponent($0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func runGit(_ arguments: [String]) throws -> String {
        let process = Process()
        process.currentDirectoryURL = repoRoot
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
