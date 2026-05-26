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
        executionTimeAllowance = 10
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
        var failures: [String] = []

        for forbidden in forbiddenLiterals {
            failures.append(contentsOf: try gitGrep(["-F", forbidden]))
        }
        failures.append(contentsOf: try gitGrep(["-E", #"(^|[^A-Za-z])"# + "pha" + "se" + #"([^A-Za-z]|$)"#]))

        XCTAssertTrue(failures.isEmpty, failures.prefix(80).joined(separator: "\n"))
    }

    private func gitGrep(_ patternArguments: [String]) throws -> [String] {
        try runGit([
            "grep", "-n", "-I"
        ] + patternArguments + [
            "--",
            ":(glob)**/*.swift",
            ":(glob)**/*.md",
            ":(glob)**/*.txt",
            ":(glob)**/*.toml",
            ":(glob)**/*.yml",
            ":(glob)**/*.yaml",
            ":(glob)**/*.json",
            ":(glob)**/*.sh",
            ":(glob)**/*.plist",
            ":(glob)**/*.template",
            ":(exclude)MerlinTests/Unit/SDDArtifactCutoverTests.swift",
            ":(exclude)MerlinTests/Unit/ProjectTaskSkillCutoverTests.swift",
            ":(exclude)MerlinTests/Unit/SDDDocumentationSweepTests.swift",
            ":(exclude)tasks/task-344a-sdd-artifact-cutover-tests.md",
            ":(exclude)tasks/task-345a-project-task-skill-tests.md",
            ":(exclude)tasks/task-346a-sdd-doc-sweep-tests.md",
            ":(exclude)build/**",
            ":(exclude)Merlin.xcodeproj/**"
        ])
        .split(separator: "\n")
        .map(String.init)
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
