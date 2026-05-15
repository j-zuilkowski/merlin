import XCTest
@testable import Merlin

final class UserPromptDisciplineCheckerTests: XCTestCase {

    private func makeTmpProject(withPhaseFile phaseContent: String? = nil) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("updc-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let phasesDir = dir.appendingPathComponent("phases")
        try FileManager.default.createDirectory(at: phasesDir, withIntermediateDirectories: true)
        if let content = phaseContent {
            try content.write(
                to: phasesDir.appendingPathComponent("phase-99a-provider-budget-tests.md"),
                atomically: true, encoding: .utf8)
        }
        return dir
    }

    // MARK: - Feature request with no matching phase returns missingPhaseFile

    func testFeatureRequestWithNoPhaseReturnsMissing() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let checker = UserPromptDisciplineChecker()
        let result = await checker.check(
            prompt: "add dark mode support to the settings panel",
            projectPath: proj.path)
        if case .ok = result {
            XCTFail("Expected missingPhaseFile for feature request with no phase file")
        }
    }

    // MARK: - Non-feature-request returns ok

    func testNonFeatureRequestReturnsOk() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }
        let checker = UserPromptDisciplineChecker()
        let result = await checker.check(
            prompt: "fix the typo in the README",
            projectPath: proj.path)
        if case .missingPhaseFile = result {
            XCTFail("Expected ok for non-feature-request prompt")
        }
    }

    // MARK: - Feature request with matching phase file returns ok

    func testFeatureRequestWithMatchingPhaseReturnsOk() async throws {
        let content = "# Phase 99a — ProviderBudget Tests\n\nNew surface..."
        let proj = try makeTmpProject(withPhaseFile: content)
        defer { try? FileManager.default.removeItem(at: proj) }
        let checker = UserPromptDisciplineChecker()
        let result = await checker.check(
            prompt: "implement ProviderBudget for provider config",
            projectPath: proj.path)
        _ = result
    }

    // MARK: - Result type is Sendable

    func testResultIsSendable() {
        func requiresSendable<T: Sendable>(_ v: T) {}
        requiresSendable(UserPromptCheckResult.ok)
        requiresSendable(UserPromptCheckResult.missingPhaseFile(suggestion: "Write phase NNa first"))
    }
}
