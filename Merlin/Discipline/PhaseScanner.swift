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
            let declared = normalisedSignature(surface: declaration.surface)
            let declaredName = normalisedName(surface: declaration.surface)
            let matches = sourceDeclarations.filter { $0.name == declaredName }

            if let exact = matches.first(where: { $0.signature == declared }) {
                findings.append(DriftFinding(
                    id: UUID(),
                    phaseID: declaration.phaseID,
                    surface: declaration.surface,
                    severity: .green,
                    evidence: "Found in \(exact.file.lastPathComponent)",
                    suggestedAction: "No action needed"
                ))
            } else if let nearMiss = matches.first {
                findings.append(DriftFinding(
                    id: UUID(),
                    phaseID: declaration.phaseID,
                    surface: declaration.surface,
                    severity: .yellow,
                    evidence: "Found \(nearMiss.signature) in \(nearMiss.file.lastPathComponent)",
                    suggestedAction: "Update the phase file or write an addendum"
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

        let nnbFiles = files
            .filter { file in
                let name = file.lastPathComponent
                return name.hasPrefix("phase-")
                    && name.hasSuffix(".md")
                    && name.range(of: #"phase-\d+b-"#, options: .regularExpression) != nil
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var result: [DeclaredSurface] = []
        for file in nnbFiles {
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
            if !symbol.isEmpty {
                surfaces.append(symbol)
            }
        }

        return surfaces
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
                guard let symbol = parseSourceDeclaration(trimmed, file: url) else { continue }
                symbols.append(symbol)
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

    private func normalisedSignature(surface: String) -> String {
        canonicalDeclaration(from: surface)
    }

    private func normalisedSignature(sourceLine line: String) -> String {
        canonicalDeclaration(from: line)
    }

    private func canonicalDeclaration(from raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)

        let removablePrefixes = [
            "public ", "internal ", "private ", "fileprivate ", "open ",
            "static ", "final ", "nonisolated ", "override ", "mutating ",
            "nonmutating "
        ]
        var changed = true
        while changed {
            changed = false
            for prefix in removablePrefixes where value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
                changed = true
            }
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
