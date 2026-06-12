import Foundation

struct DiscoveredTool: Codable, Sendable {
    var name: String
    var path: String
    var helpSummary: String?
}

enum ToolDiscovery {
    struct Request: Decodable {
        var name: String?
        var tool: String?

        var requestedName: String? {
            let raw = name ?? tool
            let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.isEmpty == false ? trimmed : nil
        }
    }

    private struct Cache: Codable {
        var pathSignature: String
        var scannedAt: Date
        var tools: [DiscoveredTool]
    }

    static var defaultCacheURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".merlin/tool-discovery-cache.json")
    }

    /// When `summarize` is true (default, production behavior), each discovered
    /// executable is probed with `--help` (2 s timeout each) to populate
    /// `helpSummary`. On a developer machine this is fast enough; on CI's
    /// macos-15 runner `$PATH` carries hundreds of binaries — many of which
    /// ignore `--help` and burn the full 2 s — so a contract-level test that
    /// just needs the tool list spent 5–15 minutes per call. Pass `false` from
    /// tests to skip the probe and return discovery-only results in
    /// milliseconds.
    static func scan(summarize: Bool = true) async -> [DiscoveredTool] {
        await scan(summarize: summarize, cacheURL: nil)
    }

    static func cachedScan(
        requestedTool: String? = nil,
        summarize: Bool = true,
        cacheURL: URL = defaultCacheURL,
        forceRefresh: Bool = false,
        pathOverride: String? = nil
    ) async -> [DiscoveredTool] {
        let pathSignature = discoveryPath(pathOverride: pathOverride)
        if !forceRefresh,
           let cache = loadCache(from: cacheURL),
           cache.pathSignature == pathSignature {
            if let requestedTool {
                if let cached = cache.tools.first(where: { $0.name == requestedTool }),
                   FileManager.default.isExecutableFile(atPath: cached.path) {
                    return [cached]
                }
            } else {
                let liveCachedTools = cache.tools.filter {
                    FileManager.default.isExecutableFile(atPath: $0.path)
                }
                if liveCachedTools.count == cache.tools.count {
                    return cache.tools
                }
            }
        }
        return await scan(
            requestedTool: requestedTool,
            summarize: summarize,
            cacheURL: cacheURL,
            pathOverride: pathOverride,
            pathSignature: pathSignature
        )
    }

    private static func scan(
        requestedTool: String? = nil,
        summarize: Bool,
        cacheURL: URL?,
        pathOverride: String? = nil,
        pathSignature: String? = nil
    ) async -> [DiscoveredTool] {
        let signature = pathSignature ?? discoveryPath(pathOverride: pathOverride)
        let uniqueTools = discoverExecutablesOnPath(pathOverride: pathOverride)
        var results: [DiscoveredTool] = []
        results.reserveCapacity(uniqueTools.count)

        for tool in uniqueTools {
            let summary = summarize ? await helpSummary(for: tool.path) : nil
            results.append(DiscoveredTool(name: tool.name, path: tool.path, helpSummary: summary))
        }

        if let cacheURL {
            saveCache(Cache(pathSignature: signature, scannedAt: Date(), tools: results), to: cacheURL)
        }
        guard let requestedTool else { return results }
        return results.filter { $0.name == requestedTool }
    }

    private struct Candidate {
        var name: String
        var path: String
    }

    private static func discoverExecutablesOnPath(pathOverride: String? = nil) -> [Candidate] {
        let envPath = discoveryPath(pathOverride: pathOverride)
        let fm = FileManager.default
        var seen = Set<String>()
        var candidates: [Candidate] = []

        for directory in envPath.split(separator: ":") {
            let dirPath = String(directory)
            guard let contents = try? fm.contentsOfDirectory(atPath: dirPath) else {
                continue
            }

            for entry in contents.sorted() {
                let fullPath = "\(dirPath)/\(entry)"
                guard fm.isExecutableFile(atPath: fullPath), seen.insert(entry).inserted else {
                    continue
                }
                candidates.append(Candidate(name: entry, path: fullPath))
            }
        }

        return candidates
    }

    private static func discoveryPath(pathOverride: String? = nil) -> String {
        let env = ProcessInfo.processInfo.environment
        return pathOverride
            ?? env["TOOL_DISCOVERY_PATH_OVERRIDE"]
            ?? env["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
    }

    private static func loadCache(from url: URL) -> Cache? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Cache.self, from: data)
    }

    private static func saveCache(_ cache: Cache, to url: URL) {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )
        try? data.write(to: url, options: .atomic)
    }

    // Tools that open GUI windows or drop into interactive REPLs when invoked — never probe these.
    private static let skipHelpProbe: Set<String> = [
        "wish", "wish8.5", "wish8.6", "tclsh", "tclsh8.5", "tclsh8.6",
        "python", "python3", "python2", "ruby", "perl", "lua", "irb",
        "osascript", "java", "scala", "R", "octave", "matlab",
    ]

    private static func helpSummary(for path: String) async -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent
        guard !skipHelpProbe.contains(name) else { return nil }
        let quoted = shellQuote(path)
        let command = "\(quoted) --help"
        guard let result = try? await ShellTool.run(command: command, cwd: nil, timeoutSeconds: 2) else {
            return nil
        }

        let combined = [result.stdout, result.stderr]
            .joined(separator: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        return combined.first
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
