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

        for file in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
        where file.pathExtension == "toml" {
            let text = try String(contentsOf: file, encoding: .utf8)
            do {
                let adapter = try TOMLAdapterParser.parse(text)
                adapters[adapter.language] = adapter
            } catch {
                // Log but continue — one bad file should not block the rest.
                TelemetryEmitter.shared.emit("discipline.adapter.parse_error", data: [
                    "file": file.lastPathComponent,
                    "error": String(describing: error)
                ])
            }
        }
    }

    // MARK: - Seed adapter installation

    /// Writes the built-in Swift+Rust seed adapter TOML files to `dir`.
    static func installSeedAdapters(into dir: String) async throws {
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: nil
        )

        try Self.swiftXcodeTOML.write(
            to: url.appendingPathComponent("swift-xcode.toml"),
            atomically: true,
            encoding: .utf8
        )
        try Self.rustCargoTOML.write(
            to: url.appendingPathComponent("rust-cargo.toml"),
            atomically: true,
            encoding: .utf8
        )
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
    regex = "if .+\\.id == \\\""
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
    reason = "must reference issue/phase"

    [[why_comment_triggers]]
    regex = "Duration::from_millis\\("
    reason = "duration is judgment"

    [[manual_coverage_patterns]]
    type = "public_api"
    regex = "^pub (fn|struct|enum|trait)"
    """
}
