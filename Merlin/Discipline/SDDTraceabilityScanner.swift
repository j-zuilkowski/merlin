import Foundation

struct SDDTraceabilityFinding: Sendable, Equatable {
    let file: String
    let issue: String
    let detail: String
    let suggestedAction: String
}

actor SDDTraceabilityScanner {
    func scan(projectPath: String) async -> [SDDTraceabilityFinding] {
        let root = URL(fileURLWithPath: projectPath, isDirectory: true)
        var findings: [SDDTraceabilityFinding] = []
        findings.append(contentsOf: scanTaskDocuments(root: root))
        findings.append(contentsOf: scanSpecMethodology(root: root))
        findings.append(contentsOf: scanVisionStatus(root: root))
        return findings
    }

    private func scanTaskDocuments(root: URL) -> [SDDTraceabilityFinding] {
        let tasksDir = root.appendingPathComponent("tasks", isDirectory: true)
        guard FileManager.default.fileExists(atPath: tasksDir.path),
              let enumerator = FileManager.default.enumerator(
                at: tasksDir,
                includingPropertiesForKeys: nil
              ) else {
            return []
        }

        var findings: [SDDTraceabilityFinding] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "md",
                  isTaskDocument(url.lastPathComponent),
                  shouldRequireTraceability(url.lastPathComponent),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let relative = relativePath(url, root: root)
            if !hasSection("Behavior", in: text) {
                findings.append(SDDTraceabilityFinding(
                    file: relative,
                    issue: "missingBehavior",
                    detail: "Task document has no ## Behavior EARS acceptance block.",
                    suggestedAction: "Add ## Behavior with WHEN/WHILE/IF/WHERE EARS statements."
                ))
            } else if !hasEARSStatement(in: section("Behavior", in: text)) {
                findings.append(SDDTraceabilityFinding(
                    file: relative,
                    issue: "missingEARSStatement",
                    detail: "## Behavior exists but contains no EARS-style SHALL statement.",
                    suggestedAction: "Add a WHEN/WHILE/WHERE ... THE ... SHALL ... or IF ... THEN ... SHALL ... statement."
                ))
            }

            guard hasSection("Traceability", in: text) else {
                findings.append(SDDTraceabilityFinding(
                    file: relative,
                    issue: "missingTraceability",
                    detail: "Task document has no ## Traceability block.",
                    suggestedAction: "Add Vision reference and Spec reference lines."
                ))
                continue
            }

            let trace = section("Traceability", in: text)
            validateReference(
                label: "Vision reference",
                expectedFile: "vision.md",
                trace: trace,
                taskFile: relative,
                root: root,
                findings: &findings
            )
            validateReference(
                label: "Spec reference",
                expectedFile: "spec.md",
                trace: trace,
                taskFile: relative,
                root: root,
                findings: &findings
            )
        }
        return findings
    }

    private func scanSpecMethodology(root: URL) -> [SDDTraceabilityFinding] {
        let spec = root.appendingPathComponent("spec.md")
        guard FileManager.default.fileExists(atPath: spec.path),
              let text = try? String(contentsOf: spec, encoding: .utf8) else { return [] }
        guard text.localizedCaseInsensitiveContains("## Spec-Driven Development Methodology"),
              text.contains("Vision reference: vision.md#spec-driven-development-alignment"),
              text.contains("Spec scope: all sections") else {
            return [SDDTraceabilityFinding(
                file: "spec.md",
                issue: "missingSpecTraceabilityPolicy",
                detail: "spec.md does not define the SDD traceability policy linking spec sections back to vision.md.",
                suggestedAction: "Add the Spec-Driven Development Methodology section with a vision reference and scope."
            )]
        }
        return []
    }

    private func scanVisionStatus(root: URL) -> [SDDTraceabilityFinding] {
        let vision = root.appendingPathComponent("vision.md")
        guard FileManager.default.fileExists(atPath: vision.path),
              let text = try? String(contentsOf: vision, encoding: .utf8) else { return [] }
        if text.localizedCaseInsensitiveContains("sdd rename")
            && text.localizedCaseInsensitiveContains("deferred for now") {
            return [SDDTraceabilityFinding(
                file: "vision.md",
                issue: "staleSDDStatus",
                detail: "vision.md still marks the SDD rename as deferred.",
                suggestedAction: "Update the SDD vision item to reflect the completed rename and remaining work."
            )]
        }
        return []
    }

    private func validateReference(
        label: String,
        expectedFile: String,
        trace: String,
        taskFile: String,
        root: URL,
        findings: inout [SDDTraceabilityFinding]
    ) {
        guard let value = traceLineValue(label, in: trace) else {
            findings.append(SDDTraceabilityFinding(
                file: taskFile,
                issue: "missing\(label.replacingOccurrences(of: " ", with: ""))",
                detail: "Traceability block has no \(label).",
                suggestedAction: "Add \(label): \(expectedFile)#..."
            ))
            return
        }
        guard value.contains(expectedFile) else {
            findings.append(SDDTraceabilityFinding(
                file: taskFile,
                issue: "wrong\(label.replacingOccurrences(of: " ", with: ""))",
                detail: "\(label) must point at \(expectedFile), got \(value).",
                suggestedAction: "Point \(label) at \(expectedFile)."
            ))
            return
        }
        let path = value.split(separator: "#", maxSplits: 1).first.map(String.init) ?? value
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path) else {
            findings.append(SDDTraceabilityFinding(
                file: taskFile,
                issue: "dangling\(label.replacingOccurrences(of: " ", with: ""))",
                detail: "\(label) points at missing file \(path).",
                suggestedAction: "Create \(path), or correct the traceability reference."
            ))
            return
        }
    }

    private func isTaskDocument(_ filename: String) -> Bool {
        filename.hasPrefix("task-") || filename.hasPrefix("diag-")
    }

    private func shouldRequireTraceability(_ filename: String) -> Bool {
        guard filename.hasPrefix("task-") else { return true }
        let taskNumber = filename
            .dropFirst("task-".count)
            .prefix { $0.isNumber }
        guard let number = Int(taskNumber) else { return true }
        return number >= 493
    }

    private func hasSection(_ title: String, in text: String) -> Bool {
        text.range(of: #"(?m)^##\s+\#(title)\s*$"#, options: .regularExpression) != nil
    }

    private func section(_ title: String, in text: String) -> String {
        let pattern = #"(?ms)^##\s+\#(title)\s*$(.*?)(?=^##\s+|\z)"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return "" }
        return String(text[range])
    }

    private func hasEARSStatement(in text: String) -> Bool {
        let conditionPattern = #"(?im)^\s*(WHEN|WHILE|WHERE)\b.+\bTHE\b.+\bSHALL\b"#
        let ifPattern = #"(?im)^\s*IF\b.+\bTHEN\b.+\bSHALL\b"#
        return text.range(of: conditionPattern, options: .regularExpression) != nil
            || text.range(of: ifPattern, options: .regularExpression) != nil
    }

    private func traceLineValue(_ label: String, in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.localizedCaseInsensitiveContains(label + ":") else { continue }
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            return trimmed[trimmed.index(after: colon)...]
                .trimmingCharacters(in: CharacterSet(charactersIn: " \t`"))
        }
        return nil
    }

    private func relativePath(_ url: URL, root: URL) -> String {
        url.path.replacingOccurrences(of: root.path + "/", with: "")
    }
}
