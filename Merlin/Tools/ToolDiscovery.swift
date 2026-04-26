import Foundation

struct DiscoveredTool: Codable, Sendable {
    var name: String
    var path: String
    var helpSummary: String?
}

enum ToolDiscovery {
    static func scan() async -> [DiscoveredTool] {
        let uniqueTools = discoverExecutablesOnPath()
        var results: [DiscoveredTool] = []
        results.reserveCapacity(uniqueTools.count)

        for tool in uniqueTools {
            let summary = await helpSummary(for: tool.path)
            results.append(DiscoveredTool(name: tool.name, path: tool.path, helpSummary: summary))
        }

        return results
    }

    private struct Candidate {
        var name: String
        var path: String
    }

    private static func discoverExecutablesOnPath() -> [Candidate] {
        let env = ProcessInfo.processInfo.environment
        let envPath = env["TOOL_DISCOVERY_PATH_OVERRIDE"]
            ?? env["PATH"]
            ?? "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
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

    private static func helpSummary(for path: String) async -> String? {
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
