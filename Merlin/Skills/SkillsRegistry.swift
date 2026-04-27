import Foundation
import Combine
import SwiftUI
import Darwin

@MainActor
final class SkillsRegistry: ObservableObject {
    @Published private(set) var skills: [Skill] = []

    private let personalDir: URL
    private let projectDir: URL?
    private var monitors: [DispatchSourceFileSystemObject] = []

    init(personalDir: URL, projectDir: URL?) {
        self.personalDir = personalDir
        self.projectDir = projectDir
        reload()
        startWatching()
    }

    convenience init(projectPath: String) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        self.init(
            personalDir: URL(fileURLWithPath: "\(home)/.merlin/skills"),
            projectDir: URL(fileURLWithPath: "\(projectPath)/.merlin/skills")
        )
    }

    func skill(named name: String) -> Skill? {
        skills.first { $0.name == name }
    }

    func enabledSkills(from skills: [Skill], disabledNames: [String]) -> [Skill] {
        skills.filter { !disabledNames.contains($0.name) }
    }

    var enabledSkills: [Skill] {
        enabledSkills(from: skills, disabledNames: AppSettings.shared.disabledSkillNames)
    }

    func reload() {
        var loaded: [Skill] = []

        if let items = try? FileManager.default.contentsOfDirectory(
            at: personalDir,
            includingPropertiesForKeys: nil
        ) {
            for directory in items where directory.hasDirectoryPath {
                if let skill = Skill.load(from: directory, isProjectScoped: false) {
                    loaded.append(skill)
                }
            }
        }

        if let projectDir,
           let items = try? FileManager.default.contentsOfDirectory(
            at: projectDir,
            includingPropertiesForKeys: nil
        ) {
            for directory in items where directory.hasDirectoryPath {
                if let skill = Skill.load(from: directory, isProjectScoped: true) {
                    loaded.removeAll { $0.name == skill.name }
                    loaded.append(skill)
                }
            }
        }

        skills = loaded.sorted { $0.name < $1.name }
    }

    func render(skill: Skill, arguments: String = "") -> String {
        Self.renderStatic(skill: skill, arguments: arguments)
    }

    static func renderStatic(skill: Skill, arguments: String = "") -> String {
        var body = resolveShellInjection(skill.body)

        if body.contains("$ARGUMENTS") {
            body = body.replacingOccurrences(of: "$ARGUMENTS", with: arguments)
        } else if !arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += "\n\nARGUMENTS: \(arguments)"
        }

        return body
    }

    private static func resolveShellInjection(_ body: String) -> String {
        var result = body

        if let blockRegex = try? NSRegularExpression(pattern: #"```!\n([\s\S]*?)```"#) {
            let matches = blockRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result),
                      let commandRange = Range(match.range(at: 1), in: result) else { continue }
                let command = String(result[commandRange])
                let output = runShell(command) ?? ""
                result.replaceSubrange(range, with: output)
            }
        }

        if let inlineRegex = try? NSRegularExpression(pattern: #"!`([^`]+)`"#) {
            let matches = inlineRegex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result),
                      let commandRange = Range(match.range(at: 1), in: result) else { continue }
                let command = String(result[commandRange])
                let output = runShell(command) ?? ""
                result.replaceSubrange(range, with: output)
            }
        }

        return result
    }

    private static func runShell(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func startWatching() {
        watch(directory: personalDir)
        if let projectDir {
            watch(directory: projectDir)
        }
    }

    private func watch(directory: URL) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        let fd = open(directory.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reload()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        monitors.append(source)
    }
}
