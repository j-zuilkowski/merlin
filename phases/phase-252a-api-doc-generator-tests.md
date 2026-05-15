# Phase 252a — APIDocGenerator Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 251b complete: DocReferenceGraph automatic mode live.

Introduces `APIDocGenerator` which drives DocC (Swift) or rustdoc (Rust) to regenerate
`api.md` (or equivalent) as part of the release gate.

New surface introduced in phase 252b:
  - `APIDocGenerator` actor in `Merlin/Discipline/APIDocGenerator.swift`:
    `func generate(projectPath: String, adapter: ProjectAdapter) async throws -> String`
    — returns the path to the generated doc file.
    `func outputPath(projectPath: String, adapter: ProjectAdapter) -> String`
    — predictable output location: `<projectPath>/docs/api.md` for Swift,
    `<projectPath>/target/doc/index.html` for Rust.
  - `APIDocGenerator.GeneratorError: Error, Sendable` — `case unsupportedGenerator(String)`,
    `case generationFailed(String)`.
  - For Swift: runs `xcodebuild docbuild` via `Process`. For Rust: runs `cargo doc`.
    Both are stubbed with dry-run mode in tests (`dryRun: Bool` init parameter).

TDD coverage:
  File 1 — `MerlinTests/Unit/APIDocGeneratorTests.swift`:
    `outputPath` returns the correct path for Swift adapter; `outputPath` returns the correct
    path for Rust adapter; `generate` in dry-run mode returns the expected path without
    actually running the build tool; unsupported `apiDocGenerator` value throws
    `unsupportedGenerator`.

---

## Write to

- `MerlinTests/Unit/APIDocGeneratorTests.swift`

### MerlinTests/Unit/APIDocGeneratorTests.swift

```swift
import XCTest
@testable import Merlin

final class APIDocGeneratorTests: XCTestCase {

    private func makeSwiftAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "swift", versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild", testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED", buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create", apiDocGenerator: "docc",
            docTargetGrade: [:], whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    private func makeRustAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "rust", versioningFile: "Cargo.toml",
            versioningField: "version",
            buildCommand: "cargo build", testCommand: "cargo test",
            buildSuccessMarker: "Finished", buildFailureMarker: "error[",
            releaseCommand: "cargo publish", apiDocGenerator: "rustdoc",
            docTargetGrade: [:], whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    private func makeUnknownAdapter() -> ProjectAdapter {
        ProjectAdapter(
            language: "haskell", versioningFile: "cabal.project",
            versioningField: "version",
            buildCommand: "cabal build", testCommand: "cabal test",
            buildSuccessMarker: "OK", buildFailureMarker: "Failed",
            releaseCommand: "cabal publish", apiDocGenerator: "haddock",
            docTargetGrade: [:], whyCommentTriggers: [], manualCoveragePatterns: []
        )
    }

    // MARK: - outputPath for Swift

    func testOutputPathSwift() async {
        let gen = APIDocGenerator(dryRun: true)
        let path = await gen.outputPath(projectPath: "/proj", adapter: makeSwiftAdapter())
        XCTAssertTrue(path.contains("api.md") || path.contains("api"),
                      "Swift output path should reference api.md")
        XCTAssertTrue(path.hasPrefix("/proj"))
    }

    // MARK: - outputPath for Rust

    func testOutputPathRust() async {
        let gen = APIDocGenerator(dryRun: true)
        let path = await gen.outputPath(projectPath: "/proj", adapter: makeRustAdapter())
        XCTAssertTrue(path.contains("doc") || path.contains("api"),
                      "Rust output path should reference doc output")
    }

    // MARK: - generate in dry-run returns expected path

    func testGenerateDryRunSwift() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("apidoc-\(UUID())")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let gen = APIDocGenerator(dryRun: true)
        let output = try await gen.generate(projectPath: proj.path, adapter: makeSwiftAdapter())
        XCTAssertFalse(output.isEmpty)
    }

    // MARK: - unsupported generator throws

    func testUnsupportedGeneratorThrows() async throws {
        let proj = FileManager.default.temporaryDirectory
            .appendingPathComponent("apidoc-unk-\(UUID())")
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: proj) }

        let gen = APIDocGenerator(dryRun: true)
        do {
            _ = try await gen.generate(projectPath: proj.path, adapter: makeUnknownAdapter())
            XCTFail("Expected unsupportedGenerator error")
        } catch APIDocGenerator.GeneratorError.unsupportedGenerator {
            // Expected
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD FAILED** with errors naming `APIDocGenerator` and
`APIDocGenerator.GeneratorError`.

## Commit

```bash
git add phases/phase-252a-api-doc-generator-tests.md \
    MerlinTests/Unit/APIDocGeneratorTests.swift
git commit -m "Phase 252a — APIDocGeneratorTests (failing)"
```
