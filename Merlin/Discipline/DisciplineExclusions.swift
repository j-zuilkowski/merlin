import Foundation

/// The directory blacklist every file-walking discipline scanner honours.
///
/// `merlin-eval/` holds the eval suite's fixtures - deliberately-buggy fixture source
/// and scenario Markdown. Scanning it raises false drift / unwired / stub / dangling-
/// reference findings, so every scanner skips any file beneath an excluded directory.
enum DisciplineExclusions {

    /// Directory names that exclude every file at or beneath them. Matched as a path
    /// *component*, not a substring, so a file merely named `merlin-eval-x` is unaffected.
    static let excludedDirectoryNames: Set<String> = ["merlin-eval"]

    /// True when `url` lies inside a blacklisted directory.
    static func isExcluded(_ url: URL) -> Bool {
        url.pathComponents.contains { excludedDirectoryNames.contains($0) }
    }
}
