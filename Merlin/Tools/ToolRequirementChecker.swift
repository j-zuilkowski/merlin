import Foundation

/// Detects whether an external CLI tool is installed and installs brew-safe tools
/// on request. The detector is injectable so tests never touch the real PATH.
actor ToolRequirementChecker {

    static let shared = ToolRequirementChecker()

    /// Returns true when `executable` resolves to an installed binary.
    typealias Detector = @Sendable (_ executable: String) async -> Bool

    enum ToolRequirementError: Error, Sendable {
        case notAutoInstallable(String)
        case installFailed(String)
        case homebrewMissing
    }

    private let detector: Detector
    private var availabilityCache: [String: Bool] = [:]

    init(detector: @escaping Detector = ToolRequirementChecker.pathDetector) {
        self.detector = detector
    }

    /// True when the tool is installed. Cached after the first lookup.
    func isAvailable(_ requirement: ToolRequirement) async -> Bool {
        if let cached = availabilityCache[requirement.id] { return cached }
        let present = await detector(requirement.executable)
        availabilityCache[requirement.id] = present
        return present
    }

    /// The requirement for `id`, but only when it is missing. nil means it is
    /// installed, or `id` is not a known requirement.
    func missingRequirement(id: String) async -> ToolRequirement? {
        guard let requirement = ToolRequirements.named(id) else { return nil }
        return await isAvailable(requirement) ? nil : requirement
    }

    /// Installs a brew-safe requirement with one `brew install <formula>`.
    func installViaHomebrew(_ requirement: ToolRequirement) async throws {
        guard case .homebrew(let formula) = requirement.install else {
            throw ToolRequirementError.notAutoInstallable(requirement.id)
        }
        guard let brew = Self.locateHomebrew() else {
            throw ToolRequirementError.homebrewMissing
        }

        let status = Self.runProcess(executable: brew, arguments: ["install", formula])
        guard status == 0 else {
            TelemetryEmitter.shared.emit("tool.requirement.install_failed", data: [
                "id": requirement.id,
                "formula": formula,
                "exit_code": Int(status)
            ])
            throw ToolRequirementError.installFailed(formula)
        }

        availabilityCache[requirement.id] = nil
        TelemetryEmitter.shared.emit("tool.requirement.installed", data: [
            "id": requirement.id,
            "formula": formula
        ])
    }

    // MARK: - Production detection

    /// Looks an executable up the way a Finder-launched app must: a GUI process
    /// inherits a stripped PATH, so `which` alone misses Homebrew/cargo binaries.
    static let pathDetector: Detector = { executable in
        if ToolRequirementChecker.runProcess(executable: "/usr/bin/which", arguments: [executable]) == 0 {
            return true
        }
        return ToolRequirementChecker.candidatePaths(for: executable).contains {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    private static func locateHomebrew() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func candidatePaths(for executable: String) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var paths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(home)/.cargo/bin",
            "\(home)/.lmstudio/bin"
        ].map { "\($0)/\(executable)" }

        if executable == "kicad-cli" {
            paths.append("/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli")
            paths.append("/Applications/KiCad/kicad-cli")
        }
        return paths
    }

    private static func runProcess(executable: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return 127
        }
    }
}
