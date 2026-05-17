import Foundation

/// One stub, placeholder, or deferred-work marker found in source.
struct StubMarkerFinding: Sendable, Equatable {
    let file: String
    let line: Int
    let marker: String
    /// True for code that aborts or does nothing if reached; false for deferral
    /// comments that merely flag future work.
    let isHardStub: Bool
    let context: String
}

/// Scans source for markers of unfinished work - code that compiles green but is not
/// actually done. Language-agnostic line scan over Swift and Rust sources.
actor StubMarkerScanner {

    private struct Marker {
        let regex: String
        let label: String
        let hard: Bool
    }

    private let markers: [Marker] = [
        Marker(regex: #"\bfatalError\s*\("#, label: "fatalError", hard: true),
        Marker(regex: #"\bpreconditionFailure\s*\("#, label: "preconditionFailure", hard: true),
        Marker(regex: #"\bunimplemented\b"#, label: "unimplemented", hard: true),
        Marker(regex: #"\bnotImplemented\b"#, label: "notImplemented", hard: true),
        Marker(regex: #"Button\([^)]*\)\s*\{\s*\}"#, label: "empty Button action", hard: true),
        Marker(regex: #"//\s*(stub|placeholder|deferred)\b"#, label: "stub comment", hard: true),
        Marker(regex: #"\bTODO\b"#, label: "TODO", hard: false),
        Marker(regex: #"\bFIXME\b"#, label: "FIXME", hard: false),
        Marker(regex: #"\bXXX\b"#, label: "XXX", hard: false),
        Marker(regex: #"\bHACK\b"#, label: "HACK", hard: false),
    ]

    func scan(projectPath: String) async -> [StubMarkerFinding] {
        var results: [StubMarkerFinding] = []
        let root = URL(fileURLWithPath: projectPath)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return results }

        while let url = enumerator.nextObject() as? URL {
            guard url.pathExtension == "swift" || url.pathExtension == "rs",
                  !url.path.contains("Tests/"),
                  !url.path.contains("/.build/"),
                  !url.path.contains("/build/"),
                  !url.path.contains("/DerivedData/"),
                  !DisciplineExclusions.isExcluded(url),
                  // The scanner's own marker table embeds the marker vocabulary.
                  url.lastPathComponent != "StubMarkerScanner.swift",
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let lines = text.components(separatedBy: .newlines)
            var inMultilineString = false
            for (idx, line) in lines.enumerated() {
                let tripleQuotes = line.components(separatedBy: "\"\"\"").count - 1
                // Lines inside a `"""` multi-line string literal are content, not code.
                if inMultilineString {
                    if tripleQuotes % 2 == 1 { inMultilineString = false }
                    continue
                }
                for marker in markers {
                    guard let range = line.range(
                        of: marker.regex, options: .regularExpression) else { continue }
                    // A marker inside a "..." string literal is data, not a code marker.
                    if isInsideStringLiteral(line: line, matchStart: range.lowerBound) {
                        continue
                    }
                    // An empty-bodied `.cancel`-role button is idiomatic SwiftUI — the
                    // dialog dismisses itself; the empty action is correct, not a stub.
                    if marker.label == "empty Button action", line.contains(".cancel") {
                        continue
                    }
                    results.append(StubMarkerFinding(
                        file: url.path,
                        line: idx + 1,
                        marker: marker.label,
                        isHardStub: marker.hard,
                        context: line.trimmingCharacters(in: .whitespaces)))
                }
                if tripleQuotes % 2 == 1 { inMultilineString = true }
            }
        }
        return results
    }

    /// True when `matchStart` lies inside a `"..."` string literal on `line`.
    private func isInsideStringLiteral(line: String, matchStart: String.Index) -> Bool {
        var insideString = false
        var previous: Character?
        var index = line.startIndex
        while index < matchStart {
            let ch = line[index]
            if ch == "\"" && previous != "\\" { insideString.toggle() }
            previous = ch
            index = line.index(after: index)
        }
        return insideString
    }
}
