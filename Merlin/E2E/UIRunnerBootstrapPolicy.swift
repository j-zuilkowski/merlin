import Foundation

enum UIRunnerBootstrapFailure: Equatable {
    case unsupportedConfiguration(String)
    case runnerBootstrap(String)
}

struct UIRunnerBootstrapResult: Equatable {
    let isAllowed: Bool
    let failure: UIRunnerBootstrapFailure?
}

struct UIRunnerBootstrapPolicy: Equatable {
    let derivedDataPath: String?
    let codeSigningAllowed: Bool
    let codeSignIdentity: String?

    static let supported = UIRunnerBootstrapPolicy(
        derivedDataPath: nil,
        codeSigningAllowed: true,
        codeSignIdentity: nil)

    func preflight() -> UIRunnerBootstrapResult {
        if let path = derivedDataPath,
           path.hasPrefix("/tmp/") || path == "/tmp",
           codeSigningAllowed == false {
            return UIRunnerBootstrapResult(
                isAllowed: false,
                failure: .unsupportedConfiguration(
                    "/tmp DerivedData with code signing disabled cannot reliably bootstrap MerlinUITests"))
        }
        return UIRunnerBootstrapResult(isAllowed: true, failure: nil)
    }

    func xcodebuildArguments(forOnlyTesting onlyTesting: String? = nil) -> [String] {
        var args = ["-scheme", "MerlinUITests", "-destination", "platform=macOS"]
        if let onlyTesting {
            args += ["-only-testing:\(onlyTesting)"]
        }
        return args + ["test"]
    }

    static func classifyXCTestOutput(_ output: String) -> UIRunnerBootstrapFailure? {
        let lower = output.lowercased()
        if lower.contains("early unexpected exit")
            && lower.contains("bootstrapping") {
            return .runnerBootstrap(
                "XCTest runner exited before establishing the automation connection")
        }
        if lower.contains("never finished bootstrapping")
            || lower.contains("before establishing connection") {
            return .runnerBootstrap(
                "XCTest runner exited before establishing the automation connection")
        }
        return nil
    }
}
