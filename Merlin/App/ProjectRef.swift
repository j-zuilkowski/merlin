import Foundation

struct ProjectRef: Codable, Hashable, Identifiable, Sendable {
    // `path` is the canonical identifier - resolved absolute path.
    var path: String
    var displayName: String
    var lastOpenedAt: Date

    var id: String { path }

    init(path: String, displayName: String, lastOpenedAt: Date = Date()) {
        self.path = path
        self.displayName = displayName
        self.lastOpenedAt = lastOpenedAt
    }

    static func make(url: URL) -> ProjectRef {
        let resolved = url.resolvingSymlinksInPath()
        return ProjectRef(
            path: resolved.path,
            displayName: resolved.lastPathComponent,
            lastOpenedAt: Date()
        )
    }
}
