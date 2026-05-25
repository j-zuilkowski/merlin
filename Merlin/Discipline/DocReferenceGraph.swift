import Foundation

actor DocReferenceGraph {
    private var builtRefs: [DocReference] = []

    func build(projectPath: String) async -> [DocReference] {
        let sourceSymbols = enumerateSourceSymbols(projectPath: projectPath)
        let symbolSet = Set(sourceSymbols.map { $0.name })
        var refs: [DocReference] = []

        for docFile in enumerateDocFiles(projectPath: projectPath) {
            guard let text = try? String(
                contentsOf: URL(fileURLWithPath: docFile), encoding: .utf8)
            else { continue }

            // Single pass: track the current heading as we encounter mentions so each
            // reference is associated with the section it actually appears under.
            var currentSection: String?
            for line in text.components(separatedBy: .newlines) {
                if line.hasPrefix("## ") || line.hasPrefix("# ") {
                    currentSection = line.trimmingCharacters(
                        in: CharacterSet(charactersIn: "# "))
                    continue
                }

                for sym in extractMentionedSymbols(from: line)
                where symbolSet.contains(sym) {
                    let sourceFile = sourceSymbols.first { $0.name == sym }?.file
                    refs.append(DocReference(
                        docFile: docFile,
                        docSection: currentSection,
                        codeSymbol: sym,
                        sourceFile: sourceFile
                    ))
                }
            }
        }

        builtRefs = refs
        return refs
    }

    /// Returns doc references that point at code symbols which do NOT exist in the
    /// source tree - genuinely broken references.
    ///
    /// `build()` returns only references whose symbols *do* exist, so a full scan can
    /// never compute staleness from it. This is the inverse query: it scans doc files
    /// for backtick-quoted identifiers that look like code symbols (PascalCase types or
    /// camelCase functions, length >= 4) and reports the ones with no matching
    /// declaration. Length-4 minimum keeps the false-positive rate on short words low.
    func danglingReferences(projectPath: String) async -> [DocReference] {
        let sourceSymbols = enumerateSourceSymbols(projectPath: projectPath)
        let symbolSet = Set(sourceSymbols.map { $0.name })
        var dangling: [DocReference] = []
        var seen: Set<String> = []

        for docFile in enumerateDocFiles(projectPath: projectPath) {
            // Task-doc Markdown is build scaffolding — never scan it for staleness.
            if docFile.contains("/tasks/") { continue }

            guard let text = try? String(
                contentsOf: URL(fileURLWithPath: docFile), encoding: .utf8)
            else { continue }

            var currentSection: String?
            var inFence = false
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") {
                    inFence.toggle()
                    continue
                }
                if !inFence, line.hasPrefix("## ") || line.hasPrefix("# ") {
                    currentSection = line.trimmingCharacters(
                        in: CharacterSet(charactersIn: "# "))
                    continue
                }
                // High-precision check only: an enum `case` declared inside a fenced
                // code block that names no real source symbol is a genuinely stale doc
                // example. A looser backticked-identifier check ran ~95% false positive
                // because it could not distinguish a stale Merlin reference from a
                // mention of an Apple or standard-library type.
                if inFence {
                    for caseName in extractEnumCaseNames(from: trimmed)
                    where caseName.count >= 4 && !symbolSet.contains(caseName) {
                        let key = "\(docFile)|\(caseName)"
                        guard !seen.contains(key) else { continue }
                        seen.insert(key)
                        dangling.append(DocReference(
                            docFile: docFile, docSection: currentSection,
                            codeSymbol: caseName, sourceFile: nil))
                    }
                }
            }
        }
        return dangling
    }

    func staleReferences(against changedSymbols: [String]) async -> [DocReference] {
        let changed = Set(changedSymbols)
        return builtRefs.filter { changed.contains($0.codeSymbol) }
    }

    private struct SymbolEntry {
        let name: String
        let file: String
    }

    private func enumerateSourceSymbols(projectPath: String) -> [SymbolEntry] {
        var entries: [SymbolEntry] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return entries }

        let sourceExtensions: Set<String> = ["swift", "rs", "py", "ts", "js"]
        for case let url as URL in enumerator {
            let p = url.path
            guard sourceExtensions.contains(url.pathExtension),
                  !p.contains("/build/"), !p.contains("/DerivedData/"),
                  !p.contains("/.build/"),
                  !DisciplineExclusions.isExcluded(url),
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }

            for line in text.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if let name = extractDeclaredSymbol(from: t) {
                    entries.append(SymbolEntry(name: name, file: url.path))
                }
                for caseName in extractEnumCaseNames(from: t) {
                    entries.append(SymbolEntry(name: caseName, file: url.path))
                }
            }
        }

        return entries
    }

    private func extractDeclaredSymbol(from line: String) -> String? {
        let patterns = [
            #"(?:public |internal |private |fileprivate )?(?:final )?(?:class|struct|enum|actor|protocol) ([A-Z][A-Za-z0-9_]+)"#,
            #"(?:public |internal |private |fileprivate )?func ([a-z][A-Za-z0-9_]+)"#,
        ]

        for pattern in patterns {
            if let match = line.range(of: pattern, options: .regularExpression) {
                let sub = String(line[match])
                let parts = sub.components(separatedBy: .whitespaces)
                if let last = parts.last, !last.isEmpty { return last }
            }
        }
        return nil
    }

    /// Enum-case identifiers declared on a trimmed `line` - `case taskDrift`, or a
    /// comma list `case a, b = "x"`. A trailing `//` line comment is stripped first so a
    /// comma inside the comment is not mistaken for a case separator (e.g.
    /// `case green // present, shape unchanged` must not yield a phantom case `shape`).
    /// Over-collecting switch-statement `case` patterns is harmless: it only adds to the
    /// known-symbol set.
    private func extractEnumCaseNames(from line: String) -> [String] {
        guard line.hasPrefix("case ") else { return [] }
        var body = line
        if let comment = body.range(of: "//") {
            body = String(body[..<comment.lowerBound])
        }
        var names: [String] = []
        for piece in body.dropFirst(5).split(separator: ",") {
            let trimmed = piece.trimmingCharacters(in: .whitespaces)
            if let r = trimmed.range(of: #"^[a-z][A-Za-z0-9_]*"#,
                                     options: .regularExpression) {
                names.append(String(trimmed[r]))
            }
        }
        return names
    }

    private func extractMentionedSymbols(from text: String) -> [String] {
        var symbols: [String] = []
        let pattern = #"`([A-Za-z][A-Za-z0-9_]+)`|([A-Z][A-Za-z0-9]{3,})"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsText = text as NSString
        let matches = regex?.matches(in: text, range: NSRange(location: 0, length: nsText.length)) ?? []

        for match in matches {
            for group in 1...2 {
                let r = match.range(at: group)
                if r.location != NSNotFound, let range = Range(r, in: text) {
                    symbols.append(String(text[range]))
                }
            }
        }

        return symbols
    }

    private func enumerateDocFiles(projectPath: String) -> [String] {
        var files: [String] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return files }
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let p = url.path
            if p.contains("/build/") || p.contains("/DerivedData/")
                || p.contains("/.build/") || DisciplineExclusions.isExcluded(url) { continue }
            files.append(p)
        }
        return files
    }
}

struct DocReference: Sendable {
    let docFile: String
    let docSection: String?
    let codeSymbol: String
    let sourceFile: String?
}
