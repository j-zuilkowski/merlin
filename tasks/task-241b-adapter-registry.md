# Task 241b — AdapterRegistry

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 241a complete: failing tests for AdapterRegistry, ProjectAdapter, WHYTriggerSpec,
ManualCoveragePattern, and seed adapter installation.

---

## Write to

### Merlin/Discipline/ProjectAdapter.swift (new file)

```swift
import Foundation

// MARK: - WHYTriggerSpec

/// A single trigger pattern that demands a nearby explanatory comment.
struct WHYTriggerSpec: Sendable, Codable, Equatable {
    let regex: String
    let reason: String
}

// MARK: - ManualCoveragePattern

/// A regex that identifies user-facing surfaces requiring manual doc coverage.
struct ManualCoveragePattern: Sendable, Codable, Equatable {
    let type: String   // e.g. "menu_item", "shortcut", "settings_field"
    let regex: String
}

// MARK: - ProjectAdapter

/// Per-language/per-toolchain configuration consumed by every v2.2 discipline component.
struct ProjectAdapter: Sendable, Codable, Equatable {
    let language: String
    let versioningFile: String
    let versioningField: String
    let buildCommand: String
    let testCommand: String
    let buildSuccessMarker: String
    let buildFailureMarker: String
    let releaseCommand: String
    let apiDocGenerator: String
    let docTargetGrade: [String: Double]
    let whyCommentTriggers: [WHYTriggerSpec]
    let manualCoveragePatterns: [ManualCoveragePattern]

    // MARK: - Stub factory (for tests and seeds)

    static func makeStub(
        language: String,
        buildCommand: String = "build"
    ) -> ProjectAdapter {
        ProjectAdapter(
            language: language,
            versioningFile: "version.txt",
            versioningField: "version",
            buildCommand: buildCommand,
            testCommand: "test",
            buildSuccessMarker: "OK",
            buildFailureMarker: "FAILED",
            releaseCommand: "release",
            apiDocGenerator: "none",
            docTargetGrade: [:],
            whyCommentTriggers: [],
            manualCoveragePatterns: []
        )
    }
}
```

### Merlin/Discipline/AdapterRegistry.swift (new file)

```swift
import Foundation

// MARK: - AdapterRegistry

/// Holds the live set of per-language project adapters.
/// Loads adapter TOML files from `~/.merlin/adapters/` at startup.
actor AdapterRegistry {

    // MARK: - Errors

    enum AdapterError: Error, Sendable {
        case notFound(String)
        case invalidFormat(String)
    }

    // MARK: - Shared singleton

    static let shared = AdapterRegistry()

    // MARK: - Storage

    private var adapters: [String: ProjectAdapter] = [:]

    // MARK: - API

    func adapter(for language: String) throws -> ProjectAdapter {
        guard let adapter = adapters[language] else {
            throw AdapterError.notFound(language)
        }
        return adapter
    }

    func register(_ adapter: ProjectAdapter, for language: String) {
        adapters[language] = adapter
    }

    /// Loads all `.toml` files from the given directory and registers their adapters.
    func loadFromDirectory(_ dir: String) async throws {
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        let contents = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        )
        for file in contents where file.pathExtension == "toml" {
            let text = try String(contentsOf: file, encoding: .utf8)
            do {
                let adapter = try TOMLAdapterParser.parse(text)
                adapters[adapter.language] = adapter
            } catch {
                // Log but continue — one bad file should not block the rest
                TelemetryEmitter.shared.emit("discipline.adapter.parse_error",
                    data: ["file": file.lastPathComponent, "error": String(describing: error)])
            }
        }
    }

    // MARK: - Seed adapter installation

    /// Writes the built-in Swift+Rust seed adapter TOML files to `dir`.
    static func installSeedAdapters(into dir: String) async throws {
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(at: url,
            withIntermediateDirectories: true, attributes: nil)

        let swiftTOML = Self.swiftXcodeTOML
        let rustTOML  = Self.rustCargoTOML

        try swiftTOML.write(
            to: url.appendingPathComponent("swift-xcode.toml"),
            atomically: true, encoding: .utf8)
        try rustTOML.write(
            to: url.appendingPathComponent("rust-cargo.toml"),
            atomically: true, encoding: .utf8)
    }

    // MARK: - Seed TOML content

    private static let swiftXcodeTOML = """
    language = "swift"
    versioning_file = "project.yml"
    versioning_field = "MARKETING_VERSION"
    build_command = "xcodebuild -scheme {scheme} build-for-testing -destination 'platform=macOS' -derivedDataPath /tmp/build CODE_SIGN_IDENTITY=\\"\\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
    test_command = "xcodebuild -scheme {scheme} test -destination 'platform=macOS' -derivedDataPath /tmp/build CODE_SIGN_IDENTITY=\\"\\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
    build_success_marker = "BUILD SUCCEEDED"
    build_failure_marker = "BUILD FAILED"
    release_command = "gh release create v{version} --notes-file RELEASE-v{version}.md --latest"
    api_doc_generator = "docc"

    [doc_target_grade]
    user_manual = 9.0
    developer_guide = 9.0
    architecture = 11.0

    [[why_comment_triggers]]
    regex = "Task\\.sleep\\("
    reason = "duration is judgment"

    [[why_comment_triggers]]
    regex = "try\\?"
    reason = "discarded error needs rationale"

    [[why_comment_triggers]]
    regex = "catch \\{ \\}"
    reason = "silenced error needs rationale"

    [[why_comment_triggers]]
    regex = "nonisolated\\(unsafe\\)"
    reason = "concurrency assertion"

    [[why_comment_triggers]]
    regex = "@unchecked Sendable"
    reason = "concurrency assertion"

    [[why_comment_triggers]]
    regex = "if .+\\.id == \\""
    reason = "special-case ID compare"

    [[manual_coverage_patterns]]
    type = "menu_item"
    regex = "CommandGroup|CommandMenu"

    [[manual_coverage_patterns]]
    type = "shortcut"
    regex = "\\.keyboardShortcut\\("

    [[manual_coverage_patterns]]
    type = "settings_field"
    regex = "AppSettings\\.[a-z][A-Za-z0-9]+"

    [[manual_coverage_patterns]]
    type = "slash_command"
    regex = "SkillRegistry\\.register"

    [[manual_coverage_patterns]]
    type = "hook_event"
    regex = "HookEvent\\.[a-z][A-Za-z0-9]+"
    """

    private static let rustCargoTOML = """
    language = "rust"
    versioning_file = "Cargo.toml"
    versioning_field = "version"
    build_command = "cargo build --workspace"
    test_command = "cargo test --workspace"
    build_success_marker = "Finished"
    build_failure_marker = "error\\["
    release_command = "cargo publish"
    api_doc_generator = "rustdoc"

    [doc_target_grade]
    user_manual = 9.0
    developer_guide = 9.0
    architecture = 11.0

    [[why_comment_triggers]]
    regex = "unsafe \\{"
    reason = "Rust convention requires // Safety:"

    [[why_comment_triggers]]
    regex = "\\.unwrap\\(\\)"
    reason = "panic point needs justification"

    [[why_comment_triggers]]
    regex = "\\.expect\\("
    reason = "panic point needs justification"

    [[why_comment_triggers]]
    regex = "transmute\\("
    reason = "always needs justification"

    [[why_comment_triggers]]
    regex = "#\\[allow\\("
    reason = "lint suppression needs rationale"

    [[why_comment_triggers]]
    regex = "todo!\\(\\)"
    reason = "must reference issue/task"

    [[why_comment_triggers]]
    regex = "Duration::from_millis\\("
    reason = "duration is judgment"

    [[manual_coverage_patterns]]
    type = "public_api"
    regex = "^pub (fn|struct|enum|trait)"
    """
}
```

### Merlin/Discipline/TOMLAdapterParser.swift (new file)

```swift
import Foundation

/// Minimal TOML parser for `ProjectAdapter` files.
/// Supports flat key-value pairs, `[table]`, and `[[array-of-tables]]`.
/// Full TOML spec not required — only the adapter subset.
enum TOMLAdapterParser {

    enum ParseError: Error, Sendable {
        case missingRequiredField(String)
        case invalidValue(String)
    }

    static func parse(_ toml: String) throws -> ProjectAdapter {
        var kv: [String: String] = [:]
        var docGrade: [String: Double] = [:]
        var whyTriggers: [WHYTriggerSpec] = []
        var coveragePatterns: [ManualCoveragePattern] = []

        var currentArrayTable: String? = nil
        var currentRegex: String? = nil
        var currentReason: String? = nil
        var currentType: String? = nil
        var currentPatternRegex: String? = nil

        let lines = toml.components(separatedBy: .newlines)
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // Array-of-tables header: [[why_comment_triggers]] etc.
            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                // flush previous array-of-table entry
                if currentArrayTable == "why_comment_triggers",
                   let r = currentRegex, let reason = currentReason {
                    whyTriggers.append(WHYTriggerSpec(regex: r, reason: reason))
                    currentRegex = nil; currentReason = nil
                } else if currentArrayTable == "manual_coverage_patterns",
                          let t = currentType, let r = currentPatternRegex {
                    coveragePatterns.append(ManualCoveragePattern(type: t, regex: r))
                    currentType = nil; currentPatternRegex = nil
                }
                currentArrayTable = String(line.dropFirst(2).dropLast(2))
                continue
            }

            // Table header: [doc_target_grade]
            if line.hasPrefix("[") && line.hasSuffix("]") && !line.hasPrefix("[[") {
                // flush previous array-of-table entry
                if currentArrayTable == "why_comment_triggers",
                   let r = currentRegex, let reason = currentReason {
                    whyTriggers.append(WHYTriggerSpec(regex: r, reason: reason))
                    currentRegex = nil; currentReason = nil
                } else if currentArrayTable == "manual_coverage_patterns",
                          let t = currentType, let r = currentPatternRegex {
                    coveragePatterns.append(ManualCoveragePattern(type: t, regex: r))
                    currentType = nil; currentPatternRegex = nil
                }
                currentArrayTable = String(line.dropFirst(1).dropLast(1))
                continue
            }

            // Key = value
            guard let eqRange = line.range(of: "=") else { continue }
            let key = line[line.startIndex..<eqRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            let rawVal = line[eqRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            let val = rawVal.hasPrefix("\"") && rawVal.hasSuffix("\"")
                ? String(rawVal.dropFirst().dropLast())
                : String(rawVal)

            switch currentArrayTable {
            case "doc_target_grade":
                if let d = Double(val) { docGrade[key] = d }
            case "why_comment_triggers":
                if key == "regex" { currentRegex = val }
                else if key == "reason" { currentReason = val }
            case "manual_coverage_patterns":
                if key == "type" { currentType = val }
                else if key == "regex" { currentPatternRegex = val }
            default:
                kv[key] = val
            }
        }

        // Flush last array-of-table entry
        if currentArrayTable == "why_comment_triggers",
           let r = currentRegex, let reason = currentReason {
            whyTriggers.append(WHYTriggerSpec(regex: r, reason: reason))
        } else if currentArrayTable == "manual_coverage_patterns",
                  let t = currentType, let r = currentPatternRegex {
            coveragePatterns.append(ManualCoveragePattern(type: t, regex: r))
        }

        guard let language = kv["language"] else {
            throw ParseError.missingRequiredField("language")
        }
        guard let versioningFile = kv["versioning_file"] else {
            throw ParseError.missingRequiredField("versioning_file")
        }
        guard let versioningField = kv["versioning_field"] else {
            throw ParseError.missingRequiredField("versioning_field")
        }

        return ProjectAdapter(
            language: language,
            versioningFile: versioningFile,
            versioningField: versioningField,
            buildCommand: kv["build_command"] ?? "",
            testCommand: kv["test_command"] ?? "",
            buildSuccessMarker: kv["build_success_marker"] ?? "BUILD SUCCEEDED",
            buildFailureMarker: kv["build_failure_marker"] ?? "BUILD FAILED",
            releaseCommand: kv["release_command"] ?? "",
            apiDocGenerator: kv["api_doc_generator"] ?? "none",
            docTargetGrade: docGrade,
            whyCommentTriggers: whyTriggers,
            manualCoveragePatterns: coveragePatterns
        )
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

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all task 241a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-241b-adapter-registry.md \
    Merlin/Discipline/ProjectAdapter.swift \
    Merlin/Discipline/AdapterRegistry.swift \
    Merlin/Discipline/TOMLAdapterParser.swift
git commit -m "Task 241b — AdapterRegistry + ProjectAdapter + seed adapters"
```
