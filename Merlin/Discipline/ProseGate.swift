import Foundation

enum ProseGateResult: Sendable {
    case pass
    case block(findings: [ReadabilityFinding])
}

actor ProseGate {

    typealias CheckerFactory = @Sendable (String, Double) -> ProseReadabilityChecker

    private let checkerFactory: CheckerFactory

    init(checkerFactory: @escaping CheckerFactory = { _, _ in ProseReadabilityChecker() }) {
        self.checkerFactory = checkerFactory
    }

    func check(changedDocFiles: [String], adapter: ProjectAdapter) async -> ProseGateResult {
        guard !changedDocFiles.isEmpty else { return .pass }

        var findings: [ReadabilityFinding] = []
        for docFile in changedDocFiles {
            let targetGrade = targetGrade(for: docFile, adapter: adapter)
            let checker = checkerFactory(docFile, targetGrade)
            let finding = await checker.check(docFile: docFile, targetGrade: targetGrade)
            if finding.measuredGrade > finding.targetGrade {
                findings.append(finding)
            }
        }

        return findings.isEmpty ? .pass : .block(findings: findings)
    }

    private func targetGrade(for docFile: String, adapter: ProjectAdapter) -> Double {
        let basename = URL(fileURLWithPath: docFile).lastPathComponent.lowercased()
        let normalized = basename.replacingOccurrences(of: "_", with: "-")

        for (pattern, grade) in adapter.docTargetGrade {
            let normalizedPattern = pattern.lowercased().replacingOccurrences(of: "_", with: "-")
            if normalized.contains(normalizedPattern) {
                return grade
            }
        }

        if normalized.contains("architecture") {
            return 11.0
        }
        return 9.0
    }
}
