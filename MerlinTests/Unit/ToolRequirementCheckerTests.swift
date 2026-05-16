import XCTest
@testable import Merlin

final class ToolRequirementCheckerTests: XCTestCase {

    // MARK: - Registry

    func testRegistryContainsKnownTools() {
        for id in ["xcodegen", "gh", "vale", "cargo", "git"] {
            XCTAssertNotNil(ToolRequirements.named(id),
                            "registry is missing required tool '\(id)'")
        }
    }

    func testBrewSafeToolIsAutoInstallable() throws {
        let xcodegen = try XCTUnwrap(ToolRequirements.named("xcodegen"))
        XCTAssertTrue(xcodegen.isAutoInstallable)
        guard case .homebrew(let formula) = xcodegen.install else {
            return XCTFail("xcodegen should install via Homebrew")
        }
        XCTAssertEqual(formula, "xcodegen")
    }

    func testNonBrewToolIsNotAutoInstallable() throws {
        // rustup is a curl-pipe-sh installer — Merlin must never run it itself.
        let cargo = try XCTUnwrap(ToolRequirements.named("cargo"))
        XCTAssertFalse(cargo.isAutoInstallable)
        guard case .manual = cargo.install else {
            return XCTFail("cargo should be a manual (detect-and-link) requirement")
        }
    }

    // MARK: - Detection

    func testIsAvailableReflectsTheDetector() async throws {
        let checker = ToolRequirementChecker(detector: { exe in exe == "git" })
        let git = try XCTUnwrap(ToolRequirements.named("git"))
        let cargo = try XCTUnwrap(ToolRequirements.named("cargo"))
        let gitPresent = await checker.isAvailable(git)
        let cargoPresent = await checker.isAvailable(cargo)
        XCTAssertTrue(gitPresent)
        XCTAssertFalse(cargoPresent)
    }

    func testMissingRequirementReturnsToolOnlyWhenAbsent() async {
        let checker = ToolRequirementChecker(detector: { exe in exe == "git" })
        let missing = await checker.missingRequirement(id: "cargo")
        XCTAssertEqual(missing?.id, "cargo", "an absent tool must be reported missing")
        let present = await checker.missingRequirement(id: "git")
        XCTAssertNil(present, "an installed tool must not be reported missing")
    }

    func testUnknownToolIdResolvesToNil() async {
        let checker = ToolRequirementChecker(detector: { _ in false })
        let result = await checker.missingRequirement(id: "not-a-real-tool")
        XCTAssertNil(result, "an unknown id must not raise a phantom requirement")
    }

    // MARK: - Install policy

    func testInstallViaHomebrewRefusesAManualTool() async throws {
        let checker = ToolRequirementChecker(detector: { _ in false })
        let cargo = try XCTUnwrap(ToolRequirements.named("cargo"))
        do {
            try await checker.installViaHomebrew(cargo)
            XCTFail("installViaHomebrew must refuse a .manual requirement")
        } catch ToolRequirementChecker.ToolRequirementError.notAutoInstallable(let id) {
            XCTAssertEqual(id, "cargo")
        }
    }

    // MARK: - Caching

    func testDetectionIsCachedPerTool() async throws {
        let counter = CallCounter()
        let checker = ToolRequirementChecker(detector: { _ in
            await counter.bump(); return true
        })
        let git = try XCTUnwrap(ToolRequirements.named("git"))
        _ = await checker.isAvailable(git)
        _ = await checker.isAvailable(git)
        let calls = await counter.value
        XCTAssertEqual(calls, 1, "detection must be cached after the first lookup")
    }

    private actor CallCounter {
        private(set) var value = 0
        func bump() { value += 1 }
    }
}
