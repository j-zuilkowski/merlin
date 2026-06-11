import Foundation

enum CapabilityConvergenceStatus: Equatable {
    case green
    case repairableFailure(String)
    case missingPrerequisite(String)
    case noProgressEscalation(String)
    case noProgressExhausted(String)
}

struct CapabilityConvergenceClassifier {
    func classify(
        verificationOutput: String,
        assistantText: String = "",
        repeatedNoProgressTurns: Int = 0,
        maxNoProgressTurns: Int = 2,
        hasFileChanges: Bool = true,
        verificationImproved: Bool = true
    ) -> CapabilityConvergenceStatus {
        let output = verificationOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerOutput = output.lowercased()

        if lowerOutput.contains("test succeeded")
            || lowerOutput.contains("test result: ok") {
            return .green
        }

        if repeatedNoProgressTurns >= maxNoProgressTurns
            && hasFileChanges == false
            && verificationImproved == false {
            return .noProgressEscalation(
                "no progress after \(repeatedNoProgressTurns) repeated turns; escalate before timeout")
        }

        if isMissingPrerequisite(lowerOutput) {
            return .missingPrerequisite(extractSummary(from: output, fallback: "missing prerequisite"))
        }

        if lowerOutput.contains("evalshell timeout")
            || lowerOutput.contains("timeout after") {
            return .repairableFailure(extractSummary(from: output, fallback: "verification timed out"))
        }

        if isRepairableVerificationFailure(lowerOutput) {
            return .repairableFailure(extractSummary(from: output, fallback: "verification failed"))
        }

        if lowerOutput.contains("failed") || lowerOutput.contains("error") {
            return .repairableFailure(extractSummary(from: output, fallback: "verification failed"))
        }

        let lowerAssistant = assistantText.lowercased()
        if lowerAssistant.contains("not available") || lowerAssistant.contains("not found") {
            return .repairableFailure(
                "model reported an environment issue, but verification output did not prove it")
        }

        return .repairableFailure(extractSummary(from: output, fallback: "verification did not pass"))
    }

    private func isMissingPrerequisite(_ lowerOutput: String) -> Bool {
        lowerOutput.contains("command not found: cargo")
            || lowerOutput.contains("env: cargo: no such file or directory")
            || lowerOutput.contains("xcodegen: command not found")
            || lowerOutput.contains("xcodebuild: command not found")
    }

    private func isRepairableVerificationFailure(_ lowerOutput: String) -> Bool {
        lowerOutput.contains("taskstoretests")
            || lowerOutput.contains("testdeleteremovesthetaskatthatindex")
            || lowerOutput.contains("tests::total_does_not_overflow_on_a_large_ledger")
            || lowerOutput.contains("attempt to add with overflow")
            || lowerOutput.contains("test result: failed")
            || lowerOutput.contains("** test failed **")
    }

    private func extractSummary(from output: String, fallback: String) -> String {
        let interesting = output
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                let lower = line.lowercased()
                return lower.contains("failed")
                    || lower.contains("test")
                    || lower.contains("overflow")
                    || lower.contains("timeout")
                    || lower.contains("command not found")
                    || lower.contains("no such file")
            }
        let summary = interesting.prefix(6).joined(separator: "\n")
        return summary.isEmpty ? fallback : summary
    }
}
