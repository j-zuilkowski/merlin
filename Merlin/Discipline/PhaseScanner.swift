import Foundation

/// Reads the `phases/` directory, extracts declared surfaces from each NNb file,
/// and cross-checks them against the current codebase.
actor PhaseScanner {

    func scan(projectPath: String) async -> [DriftFinding] {
        let root = URL(fileURLWithPath: projectPath)
        let phasesDir = root.appendingPathComponent("phases")

        let declaredSurfaces = extractDeclaredSurfaces(phasesDir: phasesDir)
        let sourceDeclarations = enumerateSourceDeclarations(root: root)

        var findings: [DriftFinding] = []
        let declaredNames = Set(declaredSurfaces.map { normalisedName(surface: $0.surface) })

        for declaration in declaredSurfaces {
            let declaredName = normalisedName(surface: declaration.surface)
            let matches = sourceDeclarations.filter { $0.name == declaredName }

            if let found = matches.first {
                findings.append(DriftFinding(
                    id: UUID(),
                    phaseID: declaration.phaseID,
                    surface: declaration.surface,
                    severity: .green,
                    evidence: "Found \(found.signature) in \(found.file.lastPathComponent)",
                    suggestedAction: "No action needed"
                ))
            } else {
                findings.append(DriftFinding(
                    id: UUID(),
                    phaseID: declaration.phaseID,
                    surface: declaration.surface,
                    severity: .red,
                    evidence: "Symbol '\(declaredName)' not found in source tree",
                    suggestedAction: "Restore symbol or write addendum phase"
                ))
            }
        }

        for symbol in sourceDeclarations where symbol.isPublic {
            if !declaredNames.contains(symbol.name) {
                findings.append(DriftFinding(
                    id: UUID(),
                    phaseID: nil,
                    surface: symbol.signature,
                    severity: .orange,
                    evidence: "Public symbol not declared in any phase NNb file",
                    suggestedAction: "Add to a phase NNb 'New surface' block"
                ))
            }
        }

        return findings
    }

    // MARK: - Helpers

    private struct DeclaredSurface {
        let surface: String
        let phaseID: String
    }

    private struct SourceSymbol {
        let name: String
        let signature: String
        let isPublic: Bool
        let file: URL
    }

    private func extractDeclaredSurfaces(phasesDir: URL) -> [DeclaredSurface] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: phasesDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        // Read every phase document — the `a` (tests) and `b` (implementation) tiers
        // and the `diag-*` series. The "New surface introduced in phase" block lives in
        // the `a` doc per the project template, so the former `phase-\d+b-` filter saw
        // almost no declared surface. Files with no such block contribute nothing.
        let phaseDocFiles = files
            .filter { file in
                let name = file.lastPathComponent
                return name.hasSuffix(".md")
                    && (name.hasPrefix("phase-") || name.hasPrefix("diag-"))
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result: [DeclaredSurface] = []
        for file in phaseDocFiles {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let phaseID = extractPhaseID(from: file.lastPathComponent)
            let surfaces = extractSurfaces(from: text)
            result.append(contentsOf: surfaces.map { DeclaredSurface(surface: $0, phaseID: phaseID) })
        }

        return result
    }

    private func extractPhaseID(from filename: String) -> String {
        let parts = filename.components(separatedBy: "-")
        if parts.count >= 2 {
            return parts[1]
        }
        return filename
    }

    private func extractSurfaces(from phaseText: String) -> [String] {
        var surfaces: [String] = []
        var inBlock = false

        for line in phaseText.components(separatedBy: .newlines) {
            if line.contains("New surface introduced in phase") {
                inBlock = true
                continue
            }

            guard inBlock else { continue }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
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

    /// A backtick-quoted "New surface" entry is a code symbol only if it looks like a
    /// Swift declaration — not a slash-command (`/compact`), a version (`2.1.0`), a
    /// file name (`Foo.swift`), or a tag (`#high-stakes`).
    private func isLikelyCodeSymbol(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty, !s.contains("/"), !s.contains("#") else { return false }
        if s.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) != nil {
            return false
        }
        for ext in [".swift", ".md", ".json", ".toml", ".txt", ".png", ".plist"]
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
            // Exclude phase docs and any test target. The test directory is named
            // `MerlinTests` (also `MerlinLiveTests`, `MerlinE2ETests`), so a literal
            // "/Tests/" match misses it - check for a path component ending in "Tests".
            if url.path.contains("/phases/") { continue }
            if url.pathComponents.contains(where: { $0.hasSuffix("Tests") }) { continue }
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
        let isPublic = line.hasPrefix("public ") || line.contains(" public ")
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
    /// Recorded so a phase doc declaring `.foo` or `Enum.foo` matches; never `isPublic`,
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
        // (`AgentEvent.criticResult` -> `criticResult`): phase docs write members
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
