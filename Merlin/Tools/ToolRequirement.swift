import Foundation

/// One external command-line tool Merlin shells out to (see Requirements.md section 10).
struct ToolRequirement: Sendable, Identifiable, Equatable {
    let id: String
    let displayName: String
    let executable: String
    let purpose: String
    let install: InstallMethod

    enum InstallMethod: Sendable, Equatable {
        /// Brew-safe: Merlin can install it with one confirmed `brew install <formula>`.
        case homebrew(formula: String)
        /// Not auto-installable. `command` and `url` are shown to the user; Merlin
        /// never runs manual installers itself.
        case manual(command: String?, url: String)
    }

    /// True only for `.homebrew`, the one-click-installable subset.
    var isAutoInstallable: Bool {
        if case .homebrew = install { return true }
        return false
    }
}

/// The known external tools, mirrored from Requirements.md section 10 / section 5 / section 7.
/// Named `ToolRequirements`, not `ToolRegistry`, to avoid shadowing the runtime tool registry.
enum ToolRequirements {

    static let all: [ToolRequirement] = [
        ToolRequirement(
            id: "xcodegen",
            displayName: "XcodeGen",
            executable: "xcodegen",
            purpose: "Regenerate the Xcode project after project.yml changes.",
            install: .homebrew(formula: "xcodegen")
        ),
        ToolRequirement(
            id: "gh",
            displayName: "GitHub CLI",
            executable: "gh",
            purpose: "Create GitHub releases.",
            install: .homebrew(formula: "gh")
        ),
        ToolRequirement(
            id: "vale",
            displayName: "Vale",
            executable: "vale",
            purpose: "Prose readability grading for Project Discipline docs.",
            install: .homebrew(formula: "vale")
        ),
        ToolRequirement(
            id: "ngspice",
            displayName: "ngspice",
            executable: "ngspice",
            purpose: "SPICE circuit simulation for the electronics domain.",
            install: .homebrew(formula: "ngspice")
        ),
        ToolRequirement(
            id: "git",
            displayName: "Git",
            executable: "git",
            purpose: "Worktree isolation, commits, and tags.",
            install: .homebrew(formula: "git")
        ),
        ToolRequirement(
            id: "cargo",
            displayName: "Rust toolchain (cargo)",
            executable: "cargo",
            purpose: "Build and test Rust projects.",
            install: .manual(
                command: "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh",
                url: "https://www.rust-lang.org/tools/install"
            )
        ),
        ToolRequirement(
            id: "python",
            displayName: "Python 3",
            executable: "python3",
            purpose: "LoRA self-training (mlx_lm).",
            install: .manual(command: nil, url: "https://www.python.org/downloads/macos/")
        ),
        ToolRequirement(
            id: "lms",
            displayName: "LM Studio CLI",
            executable: "lms",
            purpose: "LM Studio model-management fallback.",
            install: .manual(command: nil, url: "https://lmstudio.ai/")
        ),
        ToolRequirement(
            id: "kicad-cli",
            displayName: "KiCad",
            executable: "kicad-cli",
            purpose: "PCB and schematic workflows (electronics domain).",
            install: .manual(command: "brew install --cask kicad", url: "https://www.kicad.org/")
        )
    ]

    static func named(_ id: String) -> ToolRequirement? {
        all.first { $0.id == id }
    }
}
