import Foundation

@MainActor
final class WorkspaceRuntime: ObservableObject {
    let workspaceID: String
    let rootURL: URL
    let merlinHomeURL: URL
    let stateRootURL: URL
    let bus: WorkspaceMessageBus
    lazy var settingsStore = WorkspaceSettingsStore(runtime: self)
    lazy var artifactStore = WorkspaceArtifactStore(runtime: self)
    let eventCapacity: Int

    convenience init(rootURL: URL) throws {
        try self.init(rootURL: rootURL, merlinHomeURL: Self.defaultMerlinHomeURL)
    }

    init(rootURL: URL, merlinHomeURL: URL, eventCapacity: Int = 1_000) throws {
        let canonicalRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedCapacity = Self.clampedEventCapacity(eventCapacity)
        let workspaceID = try Self.resolveWorkspaceID(rootURL: canonicalRoot, merlinHomeURL: merlinHomeURL)
        let stateRootURL = merlinHomeURL
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent(workspaceID, isDirectory: true)
        self.workspaceID = workspaceID
        self.rootURL = canonicalRoot
        self.merlinHomeURL = merlinHomeURL
        self.stateRootURL = stateRootURL
        self.eventCapacity = resolvedCapacity
        self.bus = WorkspaceMessageBus(
            workspaceID: workspaceID,
            workspaceRoot: canonicalRoot,
            settingsRootURL: stateRootURL.appendingPathComponent("settings", isDirectory: true),
            eventCapacity: resolvedCapacity
        )

        try FileManager.default.createDirectory(
            at: stateRootURL.appendingPathComponent("settings", isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    func settingsURL(namespace: String) -> URL {
        stateRootURL
            .appendingPathComponent("settings", isDirectory: true)
            .appendingPathComponent("\(namespace).toml")
    }

    func loadPlugins(pluginRoots: [URL] = RuntimePluginLoader.defaultPluginRoots()) async throws {
        try await RuntimePluginLoader(pluginRoots: pluginRoots).load(into: self)
    }

    nonisolated static func clampedEventCapacity(_ requested: Int) -> Int {
        min(max(requested, 100), 10_000)
    }

    static var defaultMerlinHomeURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".merlin", isDirectory: true)
    }

    private static func resolveWorkspaceID(rootURL: URL, merlinHomeURL: URL) throws -> String {
        let indexURL = merlinHomeURL
            .appendingPathComponent("workspaces", isDirectory: true)
            .appendingPathComponent("index.toml")
        let canonicalPath = rootURL.path
        var entries = try loadIndex(from: indexURL)
        if let existing = entries[canonicalPath] {
            return existing
        }

        let id = UUID().uuidString
        entries[canonicalPath] = id
        try saveIndex(entries, to: indexURL)
        return id
    }

    private static func loadIndex(from url: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let text = try String(contentsOf: url, encoding: .utf8)
        var entries: [String: String] = [:]
        var currentPath: String?
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line == "[[workspace]]" {
                currentPath = nil
                continue
            }
            if line.hasPrefix("path = ") {
                currentPath = unquote(String(line.dropFirst("path = ".count)))
            } else if line.hasPrefix("id = "), let currentPath {
                entries[currentPath] = unquote(String(line.dropFirst("id = ".count)))
            }
        }
        return entries
    }

    private static func saveIndex(_ entries: [String: String], to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let text = entries
            .sorted { $0.key < $1.key }
            .map { path, id in
                """
                [[workspace]]
                path = "\(escape(path))"
                id = "\(escape(id))"

                """
            }
            .joined()
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func unquote(_ value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count >= 2 {
            text.removeFirst()
            text.removeLast()
        }
        return text
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

extension RuntimePluginLoader {
    static func defaultPluginRoots() -> [URL] {
        var roots: [URL] = []
        if let resourceURL = Bundle.main.resourceURL {
            roots.append(resourceURL.appendingPathComponent("plugins", isDirectory: true))
        }
        roots.append(URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("plugins", isDirectory: true))
        roots.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("plugins", isDirectory: true))
        roots.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".merlin/plugins", isDirectory: true))
        var seen: Set<String> = []
        return roots.filter { root in
            let key = root.standardizedFileURL.resolvingSymlinksInPath().path
            return seen.insert(key).inserted
        }
    }
}
