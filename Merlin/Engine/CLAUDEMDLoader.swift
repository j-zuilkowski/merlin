import Foundation

enum CLAUDEMDLoader {

    static func load(projectPath: String, globalHome: String? = defaultHome) -> String {
        let searchRoots = candidateRoots(startingAt: projectPath)
        let candidates = searchRoots.flatMap { root -> [String] in
            [
                "\(root)/CLAUDE.md",
                "\(root)/.merlin/CLAUDE.md",
            ]
        }
        + (globalHome.map { ["\($0)/CLAUDE.md"] } ?? [])

        let parts = candidates.compactMap { path -> String? in
            guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return text
        }
        return parts.joined(separator: "\n\n")
    }

    static func systemPromptBlock(projectPath: String, globalHome: String? = defaultHome) -> String {
        let content = load(projectPath: projectPath, globalHome: globalHome)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        return "[Project instructions]\n\(content)\n[/Project instructions]"
    }

    private static func candidateRoots(startingAt projectPath: String) -> [String] {
        var roots: [String] = []
        var current = URL(fileURLWithPath: projectPath).standardizedFileURL
        let fileManager = FileManager.default

        while true {
            roots.append(current.path)
            let parent = current.deletingLastPathComponent().standardizedFileURL
            guard parent.path != current.path, fileManager.fileExists(atPath: parent.path) else {
                break
            }
            current = parent
        }

        return roots
    }

    private static var defaultHome: String? {
        ProcessInfo.processInfo.environment["HOME"]
    }
}
