import Foundation

/// Reads the `tasks/` directory, extracts declared surfaces from each NNb file,
/// and cross-checks them against the current codebase.
actor TaskScanner {

    func scan(projectPath: String) async -> [DriftFinding] {
        let root = URL(fileURLWithPath: projectPath)
        let tasksDir = root.appendingPathComponent("tasks")
        let config = scanConfig(projectRoot: root)

        let declaredSurfaces = extractDeclaredSurfaces(
            tasksDir: tasksDir,
            minimumTaskNumber: config.minimumTaskNumber)
        let sourceDeclarations = enumerateSourceDeclarations(root: root)

        var findings: [DriftFinding] = []
        let declaredNames = Set(declaredSurfaces.map { normalisedName(surface: $0.surface) })

        for declaration in declaredSurfaces {
            let declaredName = normalisedName(surface: declaration.surface)
            let matches = sourceDeclarations.filter { $0.name == declaredName }

            if let found = matches.first {
                findings.append(DriftFinding(
                    id: UUID(),
                    taskID: declaration.taskID,
                    surface: declaration.surface,
                    severity: .green,
                    evidence: "Found \(found.signature) in \(found.file.lastPathComponent)",
                    suggestedAction: "No action needed"
                ))
            } else {
                findings.append(DriftFinding(
                    id: UUID(),
                    taskID: declaration.taskID,
                    surface: declaration.surface,
                    severity: .red,
                    evidence: "Symbol '\(declaredName)' not found in source tree",
                    suggestedAction: "Restore symbol or write addendum task"
                ))
            }
        }

        if config.checkUndeclaredPublicSymbols {
            for symbol in sourceDeclarations where symbol.isPublic
                && !declaredNames.contains(symbol.name) {
                findings.append(DriftFinding(
                    id: UUID(),
                    taskID: nil,
                    surface: symbol.signature,
                    severity: .orange,
                    evidence: "Public symbol not declared in any task NNb file",
                    suggestedAction: "Add to a task NNb 'New surface' block"
                ))
            }
        }

        return findings
    }

    // MARK: - Helpers

    private struct DeclaredSurface {
        let surface: String
        let taskID: String
    }

    private struct SourceSymbol {
        let name: String
        let signature: String
        let isPublic: Bool
        let file: URL
    }

    private struct TaskScanConfig {
        let minimumTaskNumber: Int?
        let checkUndeclaredPublicSymbols: Bool
    }

    private func extractDeclaredSurfaces(
        tasksDir: URL,
        minimumTaskNumber: Int?
    ) -> [DeclaredSurface] {
        // A project with no tasks/ directory has no declared surfaces. Check
        // existence first so the missing path never constructs an NSError.
        guard FileManager.default.fileExists(atPath: tasksDir.path),
              let files = try? FileManager.default.contentsOfDirectory(
            at: tasksDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        // Read every task document — the `a` (tests) and `b` (implementation) tiers
        // and the `diag-*` series. The "New surface introduced in task" block lives in
        // the `a` doc per the project template, so the former `task-\d+b-` filter saw
        // almost no declared surface. Files with no such block contribute nothing.
        let taskDocFiles = files
            .filter { file in
                let name = file.lastPathComponent
                return name.hasSuffix(".md")
                    && (name.hasPrefix("task-") || name.hasPrefix("diag-"))
            }
            .filter { file in
                guard let minimumTaskNumber else { return true }
                guard let number = taskNumber(from: file.lastPathComponent) else { return false }
                return number >= minimumTaskNumber
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let retiredNames = extractRetiredSurfaceNames(from: taskDocFiles)

        var result: [DeclaredSurface] = []
        for file in taskDocFiles {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let taskID = extractTaskID(from: file.lastPathComponent)
            let surfaces = extractSurfaces(from: text)
                .filter { !retiredNames.contains(normalisedName(surface: $0)) }
            result.append(contentsOf: surfaces.map {
                DeclaredSurface(surface: $0, taskID: taskID)
            })
        }

        return result
    }

    private func extractTaskID(from filename: String) -> String {
        let parts = filename.components(separatedBy: "-")
        if parts.count >= 2 {
            return parts[1]
        }
        return filename
    }

    private func taskNumber(from filename: String) -> Int? {
        let parts = filename.components(separatedBy: "-")
        guard parts.count >= 2 else { return nil }
        let digits = parts[1].prefix { $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }

    private func scanConfig(projectRoot: URL) -> TaskScanConfig {
        let defaults = TaskScanConfig(
            minimumTaskNumber: nil,
            checkUndeclaredPublicSymbols: true)
        let configURL = projectRoot.appendingPathComponent(".merlin/project.toml")
        guard FileManager.default.fileExists(atPath: configURL.path),
              let text = try? String(contentsOf: configURL, encoding: .utf8) else {
            return defaults
        }

        var minimumTaskNumber: Int?
        var checkUndeclaredPublic = defaults.checkUndeclaredPublicSymbols
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1)
                .first?
                .trimmingCharacters(in: .whitespaces) ?? ""
            guard !line.isEmpty else { continue }
            let pieces = line.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard pieces.count == 2 else { continue }
            switch pieces[0] {
            case "task_scan_min_number":
                minimumTaskNumber = Int(pieces[1])
            case "task_scan_public_undeclared":
                checkUndeclaredPublic = ["true", "1", "yes"]
                    .contains(pieces[1].lowercased())
            default:
                continue
            }
        }
        return TaskScanConfig(
            minimumTaskNumber: minimumTaskNumber,
            checkUndeclaredPublicSymbols: checkUndeclaredPublic)
    }

    private func extractSurfaces(from taskText: String) -> [String] {
        var surfaces: [String] = []
        var inBlock = false
        var inFence = false

        for line in taskText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                inFence.toggle()
                continue
            }
            guard !inFence else { continue }

            if line.contains("New surface introduced in task") {
                inBlock = true
                continue
            }

            guard inBlock else { continue }

            if trimmed.isEmpty {
                if !surfaces.isEmpty {
                    break
                }
                continue
            }
            if trimmed.hasPrefix("---") || trimmed.hasPrefix("##") {
                break
            }
            guard trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") else {
                continue
            }

            guard let opening = trimmed.range(of: "`") else { continue }
            let afterOpening = trimmed[opening.upperBound...]
            guard let closing = afterOpening.range(of: "`") else { continue }
            let symbol = String(afterOpening[afterOpening.startIndex..<closing.lowerBound])
            if isLikelyCodeSymbol(symbol) {
                surfaces.append(symbol)
            }
        }

        return surfaces
    }

    private func extractRetiredSurfaceNames(from taskDocFiles: [URL]) -> Set<String> {
        var retired: Set<String> = []
        for file in taskDocFiles {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var inFence = false
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    inFence.toggle()
                    continue
                }
                guard !inFence else { continue }
                let lower = trimmed.lowercased()
                guard lower.contains("retired")
                    || lower.contains("delete")
                    || lower.contains("remove")
                    || lower.contains("removed")
                    || lower.contains("no longer")
                    || lower.contains("superseded")
                else { continue }
                for symbol in backtickSymbols(in: trimmed) {
                    if let retiredName = retiredName(from: symbol) {
                        retired.insert(retiredName)
                    }
                }
            }
        }
        return retired
    }

    private func backtickSymbols(in line: String) -> [String] {
        var result: [String] = []
        var remainder = line[...]
        while let opening = remainder.firstIndex(of: "`") {
            let afterOpening = remainder[remainder.index(after: opening)...]
            guard let closing = afterOpening.firstIndex(of: "`") else { break }
            result.append(String(afterOpening[..<closing]))
            remainder = afterOpening[afterOpening.index(after: closing)...]
        }
        return result
    }

    private func retiredName(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.hasSuffix(".swift") {
            let basename = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
            return basename.isEmpty ? nil : normalisedName(surface: basename)
        }
        guard isLikelyCodeSymbol(trimmed) else { return nil }
        return normalisedName(surface: trimmed)
    }

    /// A backtick-quoted "New surface" entry is a code symbol only if it looks like a
    /// Swift declaration — not a slash-command (`/compact`), a version (`2.1.0`), a
    /// file name (`Foo.swift`), or a tag (`#high-stakes`).
    private func isLikelyCodeSymbol(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !s.contains("/"), !s.contains("#") else { return false }
        if s.contains("$") || s.contains("::") {
            return false
        }
        if s.contains("-"), !s.contains("->") {
            return false
        }
        if s.contains(" "), !s.contains("(") {
            return false
        }
        if s.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil,
           s.contains("_") {
            return false
        }
        if s.range(of: #"^[a-z0-9_.]+$"#, options: .regularExpression) != nil,
           s.contains(".") {
            return false
        }
        if s.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) != nil {
            return false
        }
        for ext in [".swift", ".md", ".json", ".toml", ".txt", ".png", ".plist", ".yml", ".yaml"]
        where s.hasSuffix(ext) {
            return false
        }
        let core = s.hasPrefix(".") ? String(s.dropFirst()) : s
        guard let first = core.first, first.isLetter || first == "_" else { return false }
        return true
    }

    private func enumerateSourceDeclarations(root: URL) -> [SourceSymbol] {
        var symbols: [SourceSymbol] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return symbols
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "swift" else { continue }
            // Exclude task docs and any test target. The test directory is named
            // `MerlinTests` (also `MerlinLiveTests`, `MerlinE2ETests`), so a literal
            // "/Tests/" match misses it - check for a path component ending in "Tests".
            if url.path.contains("/tasks/") { continue }
            if url.pathComponents.contains(where: { $0.hasSuffix("Tests") }) { continue }
            if DisciplineExclusions.isExcluded(url) { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let symbol = parseSourceDeclaration(trimmed, file: url) {
                    symbols.append(symbol)
                }
                symbols.append(contentsOf: enumCaseSymbols(in: trimmed, file: url))
            }
        }

        return symbols
    }

    private func parseSourceDeclaration(_ line: String, file: URL) -> SourceSymbol? {
        guard isSymbolDeclaration(line) else { return nil }

        let canonical = normalisedSignature(sourceLine: line)
        let name = normalisedName(signature: canonical)
        let isStoredValue = line.contains(" let ") || line.contains(" var ")
        let isAccessibilityNamespace = file.lastPathComponent == "AccessibilityID.swift"
            && name == "AccessibilityID"
        let isPublic = !isStoredValue
            && !isAccessibilityNamespace
            && (line.hasPrefix("public ") || line.contains(" public "))
        return SourceSymbol(name: name, signature: canonical, isPublic: isPublic, file: file)
    }

    private func isSymbolDeclaration(_ line: String) -> Bool {
        let prefixes = [
            "func ",
            "class ",
            "struct ",
            "enum ",
            "actor ",
            "protocol ",
            "typealias ",
            "var ",
            "let ",
            "public func",
            "public class",
            "public struct",
            "public enum",
            "public actor",
            "public protocol"
        ]
        return prefixes.contains { line.hasPrefix($0) || line.contains(" " + $0) }
    }

    /// Enum-case declarations on a `case …` source line — `case foo`, `case foo(Bar)`,
    /// or a comma list `case a, b = "x"`. A trailing `//` comment is stripped first.
    /// Recorded so a task doc declaring `.foo` or `Enum.foo` matches; never `isPublic`,
    /// so cases never enlarge the orange (undeclared-public) set.
    private func enumCaseSymbols(in line: String, file: URL) -> [SourceSymbol] {
        guard line.hasPrefix("case ") else { return [] }
        var body = line
        if let comment = body.range(of: "//") {
            body = String(body[..<comment.lowerBound])
        }
        var result: [SourceSymbol] = []
        for piece in body.dropFirst(5).split(separator: ",") {
            let canonical = canonicalDeclaration(from: String(piece))
            let name = normalisedName(signature: canonical)
            guard let first = name.first, first.isLetter || first == "_" else { continue }
            result.append(SourceSymbol(
                name: name, signature: canonical, isPublic: false, file: file))
        }
        return result
    }

    private func normalisedSignature(surface: String) -> String {
        canonicalDeclaration(from: surface)
    }

    private func normalisedSignature(sourceLine line: String) -> String {
        canonicalDeclaration(from: line)
    }

    private func canonicalDeclaration(from raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)

        // Access modifiers and declaration-kind keywords carry no identity for
        // matching: strip them so a doc's bare `Foo` matches source `actor Foo`, and
        // `func f()` matches `f()`.
        let removablePrefixes = [
            "public ", "internal ", "private ", "fileprivate ", "open ",
            "static ", "final ", "nonisolated ", "override ", "mutating ",
            "nonmutating ",
            "func ", "class ", "struct ", "enum ", "actor ", "protocol ",
            "typealias ", "var ", "let "
        ]
        var changed = true
        while changed {
            changed = false
            for prefix in removablePrefixes where value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                changed = true
            }
        }

        // Strip a leading member-access dot (`.fail`) and any leading type qualifier
        // (`AgentEvent.criticResult` -> `criticResult`): task docs write members
        // qualified, source declares them bare.
        if value.hasPrefix(".") {
            value.removeFirst()
        }
        while let dot = value.firstIndex(of: "."), dot != value.startIndex,
              value[value.startIndex..<dot].allSatisfy({
                  $0.isLetter || $0.isNumber || $0 == "_"
              }) {
            value = String(value[value.index(after: dot)...])
        }

        if let brace = value.firstIndex(of: "{") {
            value = String(value[..<brace]).trimmingCharacters(in: .whitespaces)
        }
        if let equals = value.firstIndex(of: "=") {
            value = String(value[..<equals]).trimmingCharacters(in: .whitespaces)
        }
        if let whereIndex = value.range(of: " where ")?.lowerBound {
            value = String(value[..<whereIndex]).trimmingCharacters(in: .whitespaces)
        }

        return value
    }

    private func normalisedName(surface: String) -> String {
        normalisedName(signature: normalisedSignature(surface: surface))
    }

    private func normalisedName(signature: String) -> String {
        var value = signature

        let leadingKinds = [
            "func ", "class ", "struct ", "enum ", "actor ",
            "protocol ", "var ", "let ", "typealias "
        ]
        for kind in leadingKinds where value.hasPrefix(kind) {
            value.removeFirst(kind.count)
            break
        }

        if let paren = value.firstIndex(of: "(") {
            value = String(value[..<paren])
        }
        if let colon = value.firstIndex(of: ":") {
            value = String(value[..<colon])
        }
        if let space = value.firstIndex(of: " ") {
            value = String(value[..<space])
        }

        return value.trimmingCharacters(in: .whitespaces)
    }
}
