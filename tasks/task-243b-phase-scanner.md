# Phase 243b — TaskScanner

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 243a complete: failing tests for DriftSeverity, DriftFinding, and TaskScanner.

---

## Write to

### Merlin/Discipline/DriftFinding.swift (new file)

```swift
import Foundation

/// Classification of a single task-vs-code drift finding.
enum DriftSeverity: Sendable, Equatable {
    /// Surface present; shape matches declaration.
    case green
    /// Surface present; signature differs from declaration (likely refactor).
    case yellow
    /// Surface absent from code (deleted without addendum).
    case red
    /// Code surface not declared in any task file (undocumented).
    case orange
}

/// A single drift finding from `TaskScanner`.
struct DriftFinding: Sendable, Identifiable {
    let id: UUID
    let taskID: String?
    let surface: String
    let severity: DriftSeverity
    let evidence: String
    let suggestedAction: String
}
```

### Merlin/Discipline/TaskScanner.swift (new file)

```swift
import Foundation

/// Reads the `tasks/` directory, extracts declared surfaces from each NNb file,
/// and cross-checks them against the current codebase.
actor TaskScanner {

    // MARK: - Public API

    func scan(projectPath: String) async -> [DriftFinding] {
        let root = URL(fileURLWithPath: projectPath)
        let tasksDir = root.appendingPathComponent("phases")
        var findings: [DriftFinding] = []

        // 1. Extract declared surfaces from NNb task files
        let declaredSurfaces = extractDeclaredSurfaces(tasksDir: tasksDir)

        // 2. Enumerate source symbols from .swift files
        let sourceSymbols = enumerateSourceSymbols(root: root)

        // 3. Cross-check declared vs present
        for (surface, taskID) in declaredSurfaces {
            let symbol = normaliseSymbol(surface)
            if sourceSymbols.contains(where: { $0.contains(symbol) }) {
                findings.append(DriftFinding(
                    id: UUID(), taskID: taskID, surface: surface,
                    severity: .green,
                    evidence: "Found in source tree",
                    suggestedAction: "No action needed"
                ))
            } else {
                findings.append(DriftFinding(
                    id: UUID(), taskID: taskID, surface: surface,
                    severity: .red,
                    evidence: "Symbol '\(symbol)' not found in source tree",
                    suggestedAction: "Restore symbol or write addendum phase"
                ))
            }
        }

        // 4. Orange: public symbols in source not referenced in any phase
        let declaredNames = Set(declaredSurfaces.map { normaliseSymbol($0.surface) })
        for sym in sourceSymbols where sym.hasPrefix("public ") {
            let name = extractSymbolName(sym)
            if !name.isEmpty && !declaredNames.contains(where: { name.contains($0) }) {
                findings.append(DriftFinding(
                    id: UUID(), taskID: nil,
                    surface: sym,
                    severity: .orange,
                    evidence: "Public symbol not declared in any phase NNb file",
                    suggestedAction: "Add to a phase NNb 'New surface' block"
                ))
            }
        }

        return findings
    }

    // MARK: - Helpers

    private struct SurfaceDeclaration {
        let surface: String
        let taskID: String
    }

    private func extractDeclaredSurfaces(
        tasksDir: URL
    ) -> [(surface: String, taskID: String)] {
        var result: [(String, String)] = []
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: tasksDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return result }

        let nnbFiles = files.filter { file in
            let name = file.lastPathComponent
            // Match task-NNb-* files (letter b after digits)
            return name.hasPrefix("task-") &&
                   name.hasSuffix(".md") &&
                   file.lastPathComponent.range(
                       of: #"task-\d+b-"#, options: .regularExpression) != nil
        }

        for file in nnbFiles {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let taskID = extractPhaseID(from: file.lastPathComponent)
            let surfaces = extractSurfaces(from: text)
            result.append(contentsOf: surfaces.map { ($0, taskID) })
        }
        return result
    }

    private func extractPhaseID(from filename: String) -> String {
        // "task-233b-provider-budget.md" -> "233b"
        let parts = filename.components(separatedBy: "-")
        if parts.count >= 2 { return parts[1] }
        return filename
    }

    private func extractSurfaces(from taskText: String) -> [String] {
        var surfaces: [String] = []
        var inBlock = false
        for line in taskText.components(separatedBy: .newlines) {
            if line.contains("New surface introduced in phase") {
                inBlock = true
                continue
            }
            if inBlock {
                if line.trimmingCharacters(in: .whitespaces).isEmpty
                    && !surfaces.isEmpty { break }
                if line.hasPrefix("---") { break }
                if line.hasPrefix("##") && !line.contains("surface") { break }
                // Lines like:  - `FooBar` — description
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    if let btick = trimmed.range(of: "`") {
                        let after = trimmed[btick.upperBound...]
                        if let end = after.range(of: "`") {
                            let sym = String(after[after.startIndex..<end.lowerBound])
                            if !sym.isEmpty { surfaces.append(sym) }
                        }
                    }
                }
            }
        }
        return surfaces
    }

    private func enumerateSourceSymbols(root: URL) -> [String] {
        var symbols: [String] = []
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil,
                                             options: [.skipsHiddenFiles]) else {
            return symbols
        }
        // Exclude tasks/ and tests/ directories
        for case let url as URL in enumerator {
            let path = url.path
            if path.contains("/tasks/") || path.contains("Tests/") { continue }
            guard url.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if isSymbolDeclaration(t) { symbols.append(t) }
            }
        }
        return symbols
    }

    private func isSymbolDeclaration(_ line: String) -> Bool {
        let prefixes = ["func ", "class ", "struct ", "enum ", "actor ",
                        "protocol ", "typealias ", "var ", "let ",
                        "public func", "public class", "public struct",
                        "public enum", "public actor", "public protocol"]
        return prefixes.contains { line.hasPrefix($0) || line.contains(" " + $0) }
    }

    private func normaliseSymbol(_ surface: String) -> String {
        // Strip modifiers, return base name
        var s = surface
        for prefix in ["func ", "class ", "struct ", "enum ", "actor ",
                       "protocol ", "var ", "let ", "static ", "public "] {
            s = s.replacingOccurrences(of: prefix, with: "")
        }
        // Take just the name before "(" or ":"
        if let p = s.firstIndex(of: "(") { s = String(s[s.startIndex..<p]) }
        if let p = s.firstIndex(of: ":") { s = String(s[s.startIndex..<p]) }
        return s.trimmingCharacters(in: .whitespaces)
    }

    private func extractSymbolName(_ line: String) -> String {
        normaliseSymbol(line)
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all phase 243a tests pass. No prior phase regresses.

## Commit

```bash
git add tasks/task-243b-task-scanner.md \
    Merlin/Discipline/DriftFinding.swift \
    Merlin/Discipline/TaskScanner.swift
git commit -m "Phase 243b — TaskScanner + DriftFinding + DriftSeverity"
```
