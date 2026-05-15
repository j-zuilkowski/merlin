import Foundation

/// Result of a user-prompt discipline check.
enum UserPromptCheckResult: Sendable {
    /// Prompt does not appear to be a new feature request, or a matching phase file exists.
    case ok
    /// Prompt looks like a feature request but no NNa phase file was found.
    case missingPhaseFile(suggestion: String)
}

/// Checks incoming user prompts for unscoped feature requests.
/// Returns `.missingPhaseFile` when the prompt describes a new feature that has no
/// corresponding NNa phase file in `phases/`.
actor UserPromptDisciplineChecker {

    // MARK: - Feature-request keywords

    private let featureVerbs: Set<String> = [
        "add", "implement", "build", "create", "write", "introduce",
        "develop", "make", "design", "support"
    ]

    private let nonFeatureIndicators: Set<String> = [
        "fix", "typo", "bug", "crash", "error", "broken", "regression",
        "revert", "refactor", "rename", "move", "delete", "remove"
    ]

    // MARK: - Public API

    func check(prompt: String, projectPath: String) async -> UserPromptCheckResult {
        let lower = prompt.lowercased()
        let words = lower.components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty }

        // Non-feature-request early exit.
        if words.contains(where: { nonFeatureIndicators.contains($0) }) {
            return .ok
        }

        // Feature-request detection.
        guard words.contains(where: { featureVerbs.contains($0) }) else {
            return .ok
        }

        // Extract candidate noun (first capitalized word-ish token from original).
        let candidates = extractCandidateNouns(from: prompt)

        // Check whether any NNa phase file mentions a candidate noun.
        if candidates.isEmpty {
            let suggestion = "Write a phase NNa file before implementing: /project:phase"
            return .missingPhaseFile(suggestion: suggestion)
        }

        if candidatesHaveMatchingPhase(candidates, projectPath: projectPath) {
            return .ok
        }

        let suggestion = "Write a phase NNa file before implementing: /project:phase"
        return .missingPhaseFile(suggestion: suggestion)
    }

    // MARK: - Helpers

    private func extractCandidateNouns(from prompt: String) -> [String] {
        // Look for PascalCase or multi-word feature names.
        let words = prompt.components(separatedBy: .whitespaces)
        return words.filter { word in
            let clean = word.trimmingCharacters(in: .punctuationCharacters)
            return clean.count > 3 && clean.first?.isUppercase == true
        }
    }

    private func candidatesHaveMatchingPhase(
        _ candidates: [String], projectPath: String
    ) -> Bool {
        let phasesDir = URL(fileURLWithPath: projectPath).appendingPathComponent("phases")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: phasesDir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return false }

        // NNa files only.
        let nnAFiles = files.filter { file in
            file.pathExtension == "md" &&
            file.lastPathComponent.range(of: #"phase-\d+a-"#,
                                         options: .regularExpression) != nil
        }

        for candidate in candidates {
            let lower = candidate.lowercased()
            for file in nnAFiles {
                if file.lastPathComponent.lowercased().contains(lower) { return true }
                if let text = try? String(contentsOf: file, encoding: .utf8),
                   text.lowercased().contains(lower) {
                    return true
                }
            }
        }
        return false
    }
}
