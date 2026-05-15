import Foundation

/// Per-project discipline configuration stored at `.merlin/project.toml`.
struct ProjectConfig: Sendable, Codable, Equatable {
    /// The adapter key (e.g. `"swift-xcode"`, `"rust-cargo"`).
    let adapter: String
    /// The adapter schema version this project was adopted with.
    let adapterVersion: String
    /// Active enforcement layers: `"soft_prompt"`, `"pre_commit"`.
    let disciplineLayers: [String]
    /// Uncovered-surface count at the time of `/project:adopt`. Decays each release.
    let manualCoverageBaseline: Int
    /// Number of baseline gaps the release gate requires closing per release.
    let decayPerRelease: Int
}
