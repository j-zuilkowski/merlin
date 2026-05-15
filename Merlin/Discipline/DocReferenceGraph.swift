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

            let mentioned = extractMentionedSymbols(from: text)
            var currentSection: String?
            for line in text.components(separatedBy: .newlines) {
                if line.hasPrefix("## ") || line.hasPrefix("# ") {
                    currentSection = line.trimmingCharacters(
                        in: CharacterSet(charactersIn: "# "))
                }
            }

            for sym in mentioned where symbolSet.contains(sym) {
                let sourceFile = sourceSymbols.first { $0.name == sym }?.file
                refs.append(DocReference(
                    docFile: docFile,
                    docSection: currentSection,
                    codeSymbol: sym,
                    sourceFile: sourceFile
                ))
            }
        }

        builtRefs = refs
        return refs
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
            guard sourceExtensions.contains(url.pathExtension),
                  !url.path.contains("Tests/"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            for line in text.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if let name = extractDeclaredSymbol(from: t) {
                    entries.append(SymbolEntry(name: name, file: url.path))
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
            files.append(url.path)
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
