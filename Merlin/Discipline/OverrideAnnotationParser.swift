import Foundation

/// An inline `rationale-not-needed:` annotation parsed from a source line.
struct OverrideAnnotation: Sendable {
    let rationale: String
}

/// Parses `// rationale-not-needed: <reason>` annotations from source lines.
struct OverrideAnnotationParser: Sendable {
    private let marker = "rationale-not-needed:"

    func parse(line: String) -> OverrideAnnotation? {
        guard let range = line.range(of: marker) else { return nil }
        let rationale = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !rationale.isEmpty else { return nil }
        return OverrideAnnotation(rationale: rationale)
    }
}
