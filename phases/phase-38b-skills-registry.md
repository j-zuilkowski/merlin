# Phase 38b — SkillsRegistry Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 38a complete: failing SkillsRegistryTests in place.

Note: YAML parsing is done with a minimal hand-rolled parser for the simple key: value
frontmatter format defined in skill-standard.md. No third-party packages.

---

## Write to: Merlin/Skills/SkillFrontmatter.swift

```swift
import Foundation

struct SkillFrontmatter: Sendable {
    var name: String = ""
    var description: String = ""
    var argumentHint: String = ""
    var model: String = ""
    var userInvocable: Bool = true
    var disableModelInvocation: Bool = false
    var allowedTools: [String] = []
    var context: String = ""        // "fork" for subagent isolation

    /// Parse the YAML frontmatter block (content between --- delimiters, without the delimiters).
    static func parse(_ yaml: String) -> SkillFrontmatter {
        var fm = SkillFrontmatter()
        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: ":", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }
            let key = parts[0], value = parts[1]
            switch key {
            case "name":                      fm.name = value
            case "description":               fm.description = value
            case "argument-hint":             fm.argumentHint = value
            case "model":                     fm.model = value
            case "user-invocable":            fm.userInvocable = value == "true"
            case "disable-model-invocation":  fm.disableModelInvocation = value == "true"
            case "context":                   fm.context = value
            case "allowed-tools":
                fm.allowedTools = value.components(separatedBy: " ").filter { !$0.isEmpty }
            default: break
            }
        }
        return fm
    }
}
```

---

## Write to: Merlin/Skills/Skill.swift

```swift
import Foundation

struct Skill: Identifiable, Sendable {
    var id: String { name }
    var name: String
    var frontmatter: SkillFrontmatter
    var body: String            // skill body without frontmatter
    var directory: URL          // directory containing SKILL.md
    var isProjectScoped: Bool   // true = .merlin/skills/, false = ~/.merlin/skills/

    static func load(from directory: URL, isProjectScoped: Bool) -> Skill? {
        let skillFile = directory.appendingPathComponent("SKILL.md")
        guard let raw = try? String(contentsOf: skillFile, encoding: .utf8) else { return nil }
        let (fm, body) = parseFrontmatterAndBody(raw)
        let name = fm.name.isEmpty ? directory.lastPathComponent : fm.name
        return Skill(
            name: name,
            frontmatter: fm,
            body: body,
            directory: directory,
            isProjectScoped: isProjectScoped
        )
    }

    private static func parseFrontmatterAndBody(_ raw: String) -> (SkillFrontmatter, String) {
        let lines = raw.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            return (SkillFrontmatter(), raw)
        }
        var closingIdx: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                closingIdx = i
                break
            }
        }
        guard let ci = closingIdx else {
            return (SkillFrontmatter(), raw)
        }
        let yamlLines = Array(lines[1..<ci])
        let bodyLines = Array(lines[(ci + 1)...])
        let fm = SkillFrontmatter.parse(yamlLines.joined(separator: "\n"))
        let body = bodyLines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (fm, body)
    }
}
```

---

## Write to: Merlin/Skills/SkillsRegistry.swift

```swift
import Foundation
import Combine
import SwiftUI

@MainActor
final class SkillsRegistry: ObservableObject {
    @Published private(set) var skills: [Skill] = []

    private let personalDir: URL
    private let projectDir: URL?
    private var monitor: DispatchSourceFileSystemObject?

    init(personalDir: URL, projectDir: URL?) {
        self.personalDir = personalDir
        self.projectDir  = projectDir
        reload()
        startWatching()
    }

    convenience init(projectPath: String) {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        self.init(
            personalDir: URL(fileURLWithPath: "\(home)/.merlin/skills"),
            projectDir:  URL(fileURLWithPath: "\(projectPath)/.merlin/skills")
        )
    }

    func skill(named name: String) -> Skill? {
        skills.first { $0.name == name }
    }

    func reload() {
        var loaded: [Skill] = []

        // Personal skills (lower priority)
        if let items = try? FileManager.default.contentsOfDirectory(
            at: personalDir, includingPropertiesForKeys: nil) {
            for dir in items where dir.hasDirectoryPath {
                if let skill = Skill.load(from: dir, isProjectScoped: false) {
                    loaded.append(skill)
                }
            }
        }

        // Project skills (override personal with same name)
        if let projDir = projectDir,
           let items = try? FileManager.default.contentsOfDirectory(
            at: projDir, includingPropertiesForKeys: nil) {
            for dir in items where dir.hasDirectoryPath {
                if let skill = Skill.load(from: dir, isProjectScoped: true) {
                    loaded.removeAll { $0.name == skill.name }
                    loaded.append(skill)
                }
            }
        }

        skills = loaded.sorted { $0.name < $1.name }
    }

    func render(skill: Skill, arguments: String = "") -> String {
        var body = skill.body

        // Shell injection: `!command` and ```!\n...\n``` blocks
        body = resolveShellInjection(body)

        // Argument substitution
        if body.contains("$ARGUMENTS") {
            body = body.replacingOccurrences(of: "$ARGUMENTS", with: arguments)
        } else if !arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body += "\n\nARGUMENTS: \(arguments)"
        }

        return body
    }

    // MARK: - Shell injection

    private func resolveShellInjection(_ body: String) -> String {
        // Block form: ```!\n...\n```
        var result = body
        let blockPattern = #"```!\n([\s\S]*?)```"#
        if let regex = try? NSRegularExpression(pattern: blockPattern) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result),
                      let cmdRange = Range(match.range(at: 1), in: result) else { continue }
                let cmd = String(result[cmdRange])
                let output = runShell(cmd) ?? ""
                result.replaceSubrange(range, with: output)
            }
        }
        // Inline form: !`command`
        let inlinePattern = #"!`([^`]+)`"#
        if let regex = try? NSRegularExpression(pattern: inlinePattern) {
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                guard let range = Range(match.range, in: result),
                      let cmdRange = Range(match.range(at: 1), in: result) else { continue }
                let cmd = String(result[cmdRange])
                let output = runShell(cmd) ?? ""
                result.replaceSubrange(range, with: output)
            }
        }
        return result
    }

    private func runShell(_ command: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = ["-c", command]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - File watching

    private func startWatching() {
        // Watch personalDir; project dir watching omitted for brevity (same pattern)
        let fd = open(personalDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.reload() }
        source.setCancelHandler { close(fd) }
        source.resume()
        monitor = source
    }
}
```

---

## Modify: Merlin/Sessions/LiveSession.swift

Add `SkillsRegistry` as a property:

```swift
let skillsRegistry: SkillsRegistry

init(projectRef: ProjectRef) {
    // ... existing init
    self.skillsRegistry = SkillsRegistry(projectPath: projectRef.path)
}
```

---

## Write to: Merlin/Views/SkillsPicker.swift

```swift
import SwiftUI

struct SkillsPicker: View {
    @EnvironmentObject private var registry: SkillsRegistry
    @Binding var query: String
    let onSelect: (Skill) -> Void

    private var filtered: [Skill] {
        let q = query.lowercased()
        return registry.skills.filter { skill in
            skill.frontmatter.userInvocable &&
            (q.isEmpty || skill.name.lowercased().contains(q) ||
             skill.frontmatter.description.lowercased().contains(q))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Skills")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if filtered.isEmpty {
                Text("No skills match")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(filtered) { skill in
                            Button {
                                onSelect(skill)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("/\(skill.name)")
                                        .font(.caption.monospaced().weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(skill.frontmatter.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(width: 380)
    }
}
```

Wire the `SkillsPicker` into `ChatView`: when the user types `/` at the start of the
draft field, show the `SkillsPicker` as a popover and replace the `/query` token with
the rendered skill body on selection.

---

## Modify: project.yml

Add to Merlin target sources:
- `Merlin/Skills/SkillFrontmatter.swift`
- `Merlin/Skills/Skill.swift`
- `Merlin/Skills/SkillsRegistry.swift`
- `Merlin/Views/SkillsPicker.swift`

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `SkillsRegistryTests` → 10 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Skills/SkillFrontmatter.swift \
        Merlin/Skills/Skill.swift \
        Merlin/Skills/SkillsRegistry.swift \
        Merlin/Views/SkillsPicker.swift \
        Merlin/Sessions/LiveSession.swift \
        project.yml
git commit -m "Phase 38b — SkillsRegistry + Skill + SkillsPicker"
```
