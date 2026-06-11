import Foundation

struct CapabilityVerificationStopPolicy {
    private let verificationTools: Set<String> = [
        "run_shell",
        "xcode_test"
    ]

    func shouldStop(toolName: String, result: String) -> Bool {
        guard verificationTools.contains(toolName) else { return false }
        return CapabilityConvergenceClassifier()
            .classify(verificationOutput: result) == .green
    }

    func shouldStopAfterSourceEdit(
        toolName: String,
        arguments: String,
        isError: Bool
    ) -> Bool {
        guard toolName == "write_file", isError == false else { return false }
        guard let path = pathArgument(from: arguments) else { return false }
        return (path.hasSuffix(".swift") || path.hasSuffix(".rs"))
            && path.contains("/Tests/") == false
            && path.contains("Tests/") == false
    }

    private func pathArgument(from arguments: String) -> String? {
        guard let data = arguments.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = object["path"] as? String else {
            return nil
        }
        return path
    }
}
