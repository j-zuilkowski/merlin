# Task 287a — Tool Requirement Checker Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 286b complete: every `provider.complete` send is routed through `PreflightGuard`.

**The gap.** `Requirements.md` §10 lists the external CLI tools Merlin shells out to —
`git`, `xcodegen`, `gh`, `vale`, `cargo`, `python`, `lms`, KiCad. When one is absent the
user sees a raw "command not found" from a failed subprocess deep inside a feature, with
no hint of what is missing or how to get it. Merlin is non-sandboxed and already detects
tool presence ad hoc (`task-00-preflight.sh` does exactly this at build time) — it just
never does it *in-app, on first use*.

This task adds a declarative tool-requirement registry and a checker that detects
presence and, for the brew-safe subset, installs the tool with one confirmed
`brew install`. The 80/20: Merlin auto-installs only the Homebrew-safe formulae; for
everything else (rustup's curl-pipe-sh, Python, the LM Studio / KiCad apps) it shows the
requirement and the install command/URL but never runs the installer itself.

New surface introduced in task 287b:
  - `ToolRequirement` struct + `ToolRequirement.InstallMethod` enum in
    `Merlin/Tools/ToolRequirement.swift`:
    ```swift
    struct ToolRequirement: Sendable, Identifiable, Equatable {
        let id: String            // "xcodegen"
        let displayName: String   // "XcodeGen"
        let executable: String    // PATH lookup name
        let purpose: String       // why Merlin needs it
        let install: InstallMethod
        enum InstallMethod: Sendable, Equatable {
            case homebrew(formula: String)            // brew-safe → one-click install
            case manual(command: String?, url: String) // detect-and-link only
        }
        var isAutoInstallable: Bool   // true only for .homebrew
    }
    ```
  - `ToolRequirements` enum (the registry) in the same file:
    ```swift
    enum ToolRequirements {
        static let all: [ToolRequirement]
        static func named(_ id: String) -> ToolRequirement?
    }
    ```
    (Named `ToolRequirements`, NOT `ToolRegistry` — `ToolRegistry.shared` is the
    runtime built-in tool registry and must not be shadowed.)
  - `ToolRequirementChecker` actor in `Merlin/Tools/ToolRequirementChecker.swift`:
    ```swift
    actor ToolRequirementChecker {
        typealias Detector = @Sendable (_ executable: String) async -> Bool
        init(detector: @escaping Detector = ToolRequirementChecker.pathDetector)
        static let shared: ToolRequirementChecker
        func isAvailable(_ requirement: ToolRequirement) async -> Bool
        func missingRequirement(id: String) async -> ToolRequirement?
        func installViaHomebrew(_ requirement: ToolRequirement) async throws
        enum ToolRequirementError: Error, Sendable {
            case notAutoInstallable(String)
            case installFailed(String)
            case homebrewMissing
        }
    }
    ```

TDD coverage:
  File 1 — `MerlinTests/Unit/ToolRequirementCheckerTests.swift`: the registry contains
    the known tools with the correct install classification; an injected detector drives
    `isAvailable` / `missingRequirement` deterministically; an unknown id resolves to
    nil; `installViaHomebrew` refuses a `.manual` tool; detection is cached per tool.

---

## Write to: MerlinTests/Unit/ToolRequirementCheckerTests.swift

```swift
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
```

---

## Verify

```bash
xcodegen generate

xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** — errors naming the missing `ToolRequirement`,
`ToolRequirements`, and `ToolRequirementChecker` types.

## Commit

```bash
git add tasks/task-287a-tool-requirement-checker-tests.md \
    MerlinTests/Unit/ToolRequirementCheckerTests.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Task 287a — ToolRequirementCheckerTests (failing)"
```

(Run `xcodegen generate` so the new test file registers.)
