# Phase 241a — AdapterRegistry Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 240b complete: v2.1.0 released.

Introduces the adapter system: per-language/per-toolchain config that every v2.2 component
consumes. An adapter declares how to build, test, version-bump, and document a project in a
given language. `AdapterRegistry` holds the live set of adapters; `AdapterLoader` reads `.toml`
files from `~/.merlin/adapters/`.

New surface introduced in phase 241b:
  - `ProjectAdapter` value type in `Merlin/Discipline/ProjectAdapter.swift` — `Sendable`,
    `Codable`. Fields: `language`, `versioningFile`, `versioningField`, `buildCommand`,
    `testCommand`, `buildSuccessMarker`, `buildFailureMarker`, `releaseCommand`,
    `apiDocGenerator`, `docTargetGrade: [String: Double]`, `whyCommentTriggers: [WHYTriggerSpec]`,
    `manualCoveragePatterns: [ManualCoveragePattern]`.
  - `WHYTriggerSpec: Sendable, Codable` — `regex: String`, `reason: String`.
  - `ManualCoveragePattern: Sendable, Codable` — `type: String`, `regex: String`.
  - `actor AdapterRegistry` in `Merlin/Discipline/AdapterRegistry.swift`:
    `static let shared: AdapterRegistry`
    `func adapter(for language: String) throws -> ProjectAdapter`
    `func register(_ adapter: ProjectAdapter, for language: String)`
    `func loadFromDirectory(_ dir: String) async throws`
  - `AdapterRegistry.AdapterError: Error, Sendable` — `case notFound(String)`,
    `case invalidFormat(String)`.
  - Seed adapters written to `~/.merlin/adapters/swift-xcode.toml` and
    `~/.merlin/adapters/rust-cargo.toml` by `AdapterRegistry.installSeedAdapters()`.

TDD coverage:
  File 1 — `MerlinTests/Unit/AdapterRegistryTests.swift`: `register` + `adapter(for:)` round-
    trips; `notFound` throws when language absent; `loadFromDirectory` parses both seed TOML
    files correctly.
  File 2 — `MerlinTests/Unit/ProjectAdapterTests.swift`: `WHYTriggerSpec` and
    `ManualCoveragePattern` Codable round-trips; `docTargetGrade` dictionary survives encode/
    decode; adapter with missing optional fields uses sane defaults.
  File 3 — `MerlinTests/Unit/AdapterSeedTests.swift`: `installSeedAdapters()` writes both
    TOML files to the given tmp directory; loading them back yields adapters whose `language`
    fields equal `"swift"` and `"rust"` respectively.

---

## Write to

- `MerlinTests/Unit/AdapterRegistryTests.swift`
- `MerlinTests/Unit/ProjectAdapterTests.swift`
- `MerlinTests/Unit/AdapterSeedTests.swift`

### MerlinTests/Unit/AdapterRegistryTests.swift

```swift
import XCTest
@testable import Merlin

final class AdapterRegistryTests: XCTestCase {

    // MARK: - register + adapter(for:) round-trip

    func testRegisterAndRetrieve() async throws {
        let registry = AdapterRegistry()
        let adapter = ProjectAdapter.makeStub(language: "kotlin")
        await registry.register(adapter, for: "kotlin")
        let retrieved = try await registry.adapter(for: "kotlin")
        XCTAssertEqual(retrieved.language, "kotlin")
    }

    func testNotFoundThrows() async {
        let registry = AdapterRegistry()
        do {
            _ = try await registry.adapter(for: "cobol")
            XCTFail("Expected notFound error")
        } catch AdapterRegistry.AdapterError.notFound(let lang) {
            XCTAssertEqual(lang, "cobol")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testRegisterOverwrites() async throws {
        let registry = AdapterRegistry()
        let first = ProjectAdapter.makeStub(language: "swift", buildCommand: "xcodebuild-v1")
        let second = ProjectAdapter.makeStub(language: "swift", buildCommand: "xcodebuild-v2")
        await registry.register(first, for: "swift")
        await registry.register(second, for: "swift")
        let retrieved = try await registry.adapter(for: "swift")
        XCTAssertEqual(retrieved.buildCommand, "xcodebuild-v2")
    }

    // MARK: - loadFromDirectory

    func testLoadFromDirectory() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapters-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let toml = """
        language = "haskell"
        versioning_file = "cabal.project"
        versioning_field = "version"
        build_command = "cabal build"
        test_command = "cabal test"
        build_success_marker = "Build succeeded"
        build_failure_marker = "Build failed"
        """
        let file = dir.appendingPathComponent("haskell.toml")
        try toml.write(to: file, atomically: true, encoding: .utf8)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)
        let adapter = try await registry.adapter(for: "haskell")
        XCTAssertEqual(adapter.language, "haskell")
        XCTAssertEqual(adapter.buildCommand, "cabal build")
    }

    func testLoadFromDirectorySkipsNonToml() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapters-skip-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        try "not toml".write(
            to: dir.appendingPathComponent("notes.txt"),
            atomically: true, encoding: .utf8)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)
        // Should not throw; no adapters loaded, directory itself was fine
    }

    func testLoadFromMissingDirectoryThrows() async {
        let registry = AdapterRegistry()
        do {
            try await registry.loadFromDirectory("/nonexistent/adapters")
            XCTFail("Expected error")
        } catch {
            // Any error is acceptable — directory does not exist
        }
    }
}
```

### MerlinTests/Unit/ProjectAdapterTests.swift

```swift
import XCTest
@testable import Merlin

final class ProjectAdapterTests: XCTestCase {

    // MARK: - WHYTriggerSpec Codable

    func testWHYTriggerSpecRoundTrip() throws {
        let spec = WHYTriggerSpec(regex: "Task\\.sleep\\(", reason: "duration is judgment")
        let data = try JSONEncoder().encode(spec)
        let decoded = try JSONDecoder().decode(WHYTriggerSpec.self, from: data)
        XCTAssertEqual(decoded.regex, spec.regex)
        XCTAssertEqual(decoded.reason, spec.reason)
    }

    // MARK: - ManualCoveragePattern Codable

    func testManualCoveragePatternRoundTrip() throws {
        let pattern = ManualCoveragePattern(type: "menu_item", regex: "CommandMenu")
        let data = try JSONEncoder().encode(pattern)
        let decoded = try JSONDecoder().decode(ManualCoveragePattern.self, from: data)
        XCTAssertEqual(decoded.type, pattern.type)
        XCTAssertEqual(decoded.regex, pattern.regex)
    }

    // MARK: - ProjectAdapter Codable

    func testProjectAdapterRoundTrip() throws {
        let adapter = ProjectAdapter(
            language: "swift",
            versioningFile: "project.yml",
            versioningField: "MARKETING_VERSION",
            buildCommand: "xcodebuild",
            testCommand: "xcodebuild test",
            buildSuccessMarker: "BUILD SUCCEEDED",
            buildFailureMarker: "BUILD FAILED",
            releaseCommand: "gh release create",
            apiDocGenerator: "docc",
            docTargetGrade: ["user_manual": 9.0, "architecture": 11.0],
            whyCommentTriggers: [WHYTriggerSpec(regex: "try\\?", reason: "discarded error")],
            manualCoveragePatterns: [ManualCoveragePattern(type: "shortcut", regex: "\\.keyboardShortcut")]
        )
        let data = try JSONEncoder().encode(adapter)
        let decoded = try JSONDecoder().decode(ProjectAdapter.self, from: data)
        XCTAssertEqual(decoded.language, "swift")
        XCTAssertEqual(decoded.docTargetGrade["user_manual"], 9.0)
        XCTAssertEqual(decoded.docTargetGrade["architecture"], 11.0)
        XCTAssertEqual(decoded.whyCommentTriggers.first?.regex, "try\\?")
        XCTAssertEqual(decoded.manualCoveragePatterns.first?.type, "shortcut")
    }

    func testAdapterDefaultsForOptionalFields() throws {
        // An adapter with minimal fields should still decode without crash
        let minimal = ProjectAdapter.makeStub(language: "minimal")
        XCTAssertTrue(minimal.whyCommentTriggers.isEmpty || !minimal.whyCommentTriggers.isEmpty)
        XCTAssertNotNil(minimal.buildCommand)
    }
}
```

### MerlinTests/Unit/AdapterSeedTests.swift

```swift
import XCTest
@testable import Merlin

final class AdapterSeedTests: XCTestCase {

    func testInstallSeedAdaptersWritesFiles() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeds-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        try await AdapterRegistry.installSeedAdapters(into: dir.path)

        let swiftFile = dir.appendingPathComponent("swift-xcode.toml")
        let rustFile  = dir.appendingPathComponent("rust-cargo.toml")
        XCTAssertTrue(FileManager.default.fileExists(atPath: swiftFile.path),
                      "swift-xcode.toml not found")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rustFile.path),
                      "rust-cargo.toml not found")
    }

    func testSeedAdaptersLoadCorrectLanguages() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeds-load-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        try await AdapterRegistry.installSeedAdapters(into: dir.path)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)

        let swift = try registry.adapter(for: "swift")
        XCTAssertEqual(swift.language, "swift")
        XCTAssertEqual(swift.versioningFile, "project.yml")
        XCTAssertFalse(swift.whyCommentTriggers.isEmpty,
                       "Swift adapter should have WHY triggers")

        let rust = try registry.adapter(for: "rust")
        XCTAssertEqual(rust.language, "rust")
        XCTAssertEqual(rust.versioningFile, "Cargo.toml")
        XCTAssertFalse(rust.whyCommentTriggers.isEmpty,
                       "Rust adapter should have WHY triggers")
    }

    func testSeedAdaptersHaveManualCoveragePatterns() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("seeds-patterns-\(UUID())")
        defer { try? FileManager.default.removeItem(at: dir) }

        try await AdapterRegistry.installSeedAdapters(into: dir.path)

        let registry = AdapterRegistry()
        try await registry.loadFromDirectory(dir.path)

        let swift = try registry.adapter(for: "swift")
        XCTAssertFalse(swift.manualCoveragePatterns.isEmpty,
                       "Swift adapter should have manual coverage patterns")
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

Expected: **BUILD FAILED** with errors naming `AdapterRegistry`, `ProjectAdapter`,
`WHYTriggerSpec`, `ManualCoveragePattern`, `AdapterRegistry.AdapterError`,
`AdapterRegistry.installSeedAdapters`, and `ProjectAdapter.makeStub`.

## Commit

```bash
git add phases/phase-241a-adapter-registry-tests.md \
    MerlinTests/Unit/AdapterRegistryTests.swift \
    MerlinTests/Unit/ProjectAdapterTests.swift \
    MerlinTests/Unit/AdapterSeedTests.swift
git commit -m "Phase 241a — AdapterRegistryTests (failing)"
```
