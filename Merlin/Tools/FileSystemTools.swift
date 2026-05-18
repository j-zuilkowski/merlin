import Foundation

enum FileSystemTools {
    private static let imageExtensions: Set<String> =
        ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic"]

    static func readFile(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        // read_file decodes as UTF-8 text; an image yields garbage. Redirect the
        // caller to vision_query, which routes the image to the vision model.
        if imageExtensions.contains(url.pathExtension.lowercased()) {
            return "[\(url.lastPathComponent) is an image file — read_file cannot show "
                + "image content. Use the vision_query tool with "
                + "image_id=\"\(path)\" and a prompt describing what to extract.]"
        }
        let data = try Data(contentsOf: url)
        let text = String(decoding: data, as: UTF8.self)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.enumerated().map { "\($0.offset + 1)\t\($0.element)" }.joined(separator: "\n")
    }

    static func writeFile(path: String, content: String) async throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    static func createFile(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: url.path, contents: Data(), attributes: nil)
    }

    static func deleteFile(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Directories skipped during recursive enumeration to avoid runaway output
    /// (build artefacts, dependency caches, VCS objects).
    private static let skipDirs: Set<String> = [
        "target", ".git", "node_modules", ".build", "DerivedData",
        ".swiftpm", "Pods", "vendor", ".hg", "__pycache__", ".tox",
        "dist", "build", ".gradle", ".idea", ".vscode",
    ]

    static func listDirectory(path: String, recursive: Bool) async throws -> String {
        let url = URL(fileURLWithPath: path)
        let fm = FileManager.default
        if recursive {
            guard let enumerator = fm.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [],
                errorHandler: nil
            ) else { return "" }

            var results: [String] = []
            let limit = 500
            while let fileURL = enumerator.nextObject() as? URL {
                // Skip known huge directories entirely.
                if skipDirs.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }
                results.append(fileURL.path)
                if results.count >= limit {
                    results.append("… (truncated at \(limit) entries — use search_files for deeper exploration)")
                    break
                }
            }
            return results.sorted().joined(separator: "\n")
        } else {
            return try fm.contentsOfDirectory(atPath: url.path).sorted().joined(separator: "\n")
        }
    }

    static func moveFile(src: String, dst: String) async throws {
        let fm = FileManager.default
        let dstURL = URL(fileURLWithPath: dst)
        try fm.createDirectory(at: dstURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dst) {
            try fm.removeItem(atPath: dst)
        }
        try fm.moveItem(atPath: src, toPath: dst)
    }

    static func searchFiles(path: String, pattern: String, contentPattern: String?) async throws -> String {
        let rootURL = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: nil) else { return "" }

        let matched = enumerator.compactMap { $0 as? URL }.filter { url in
            globMatches(url.lastPathComponent, pattern: pattern)
        }.filter { url in
            guard let contentPattern else { return true }
            guard let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) else {
                return false
            }
            return content.contains(contentPattern)
        }

        return matched.map(\.path).sorted().joined(separator: "\n")
    }

    static func searchFiles(pattern: String, path: String, contentPattern: String?) async throws -> String {
        try await searchFiles(path: path, pattern: pattern, contentPattern: contentPattern)
    }

    private static func globMatches(_ value: String, pattern: String) -> Bool {
        let regexPattern = "^" + pattern
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ".", with: "\\.")
            .replacingOccurrences(of: "*", with: ".*")
            .replacingOccurrences(of: "?", with: ".") + "$"
        return (try? NSRegularExpression(pattern: regexPattern))
            .map { $0.firstMatch(in: value, options: [], range: NSRange(value.startIndex..., in: value)) != nil } ?? false
    }
}
