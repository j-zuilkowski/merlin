import Foundation
import PDFKit
import UniformTypeIdentifiers

enum AttachmentError: Error {
    case unsupportedType
    case readFailed(Error)
}

enum ContextInjector {

    private static let maxLines = 2_000

    static func resolveAtMentions(in text: String, projectPath: String) -> String {
        let pattern = #"@([^\s:,;]+)(?::(\d+)-(\d+))?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard !matches.isEmpty else { return text }

        var result = text
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: text) else { continue }
            guard let pathRange = Range(match.range(at: 1), in: text) else { continue }

            let relativePath = String(text[pathRange])
            let fileURL = URL(fileURLWithPath: projectPath).appendingPathComponent(relativePath)
            guard let raw = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }

            var lines = raw.components(separatedBy: "\n")
            var truncated = false

            let hasRange = match.range(at: 2).location != NSNotFound && match.range(at: 3).location != NSNotFound
            if hasRange,
               let startRange = Range(match.range(at: 2), in: text),
               let endRange = Range(match.range(at: 3), in: text),
               let start = Int(text[startRange]),
               let end = Int(text[endRange]) {
                let lower = max(0, start - 1)
                let upper = min(lines.count - 1, end - 1)
                if lower <= upper {
                    lines = Array(lines[lower...upper])
                } else {
                    lines = []
                }
            } else if lines.count > maxLines {
                lines = Array(lines.prefix(maxLines))
                truncated = true
            }

            var block = "[File: \(relativePath)]\n" + lines.joined(separator: "\n")
            if truncated {
                block += "\n[truncated — file exceeds \(maxLines) lines]"
            }
            block += "\n"
            result.replaceSubrange(fullRange, with: block)
        }

        return result
    }

    static func inlineAttachment(url: URL) async throws -> String {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent

        if ext == "pdf" {
            return try inlinePDF(url: url, name: name)
        }

        if sourceExtensions.contains(ext) {
            return try inlineSourceFile(url: url, name: name)
        }

        if imageExtensions.contains(ext) {
            return "[Image: \(name) — vision analysis pending]\n"
        }

        throw AttachmentError.unsupportedType
    }

    private static let sourceExtensions: Set<String> = [
        "swift", "md", "markdown", "txt", "json", "yaml", "yml", "toml",
        "xml", "html", "css", "js", "ts", "tsx", "jsx", "py", "go", "rs",
        "java", "kt", "c", "cpp", "h", "hpp", "m", "mm", "sh", "zsh", "bash",
        "sql", "graphql", "proto", "env"
    ]

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "gif", "webp"]

    private static func inlineSourceFile(url: URL, name: String) throws -> String {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            var lines = text.components(separatedBy: "\n")
            var truncated = false
            if lines.count > maxLines {
                lines = Array(lines.prefix(maxLines))
                truncated = true
            }

            var block = "[File: \(name)]\n" + lines.joined(separator: "\n") + "\n"
            if truncated {
                block += "[truncated — file exceeds \(maxLines) lines]\n"
            }
            return block
        } catch {
            throw AttachmentError.readFailed(error)
        }
    }

    private static func inlinePDF(url: URL, name: String) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw AttachmentError.readFailed(CocoaError(.fileReadUnknown))
        }

        var pages: [String] = []
        for index in 0..<document.pageCount {
            if let page = document.page(at: index), let text = page.string {
                pages.append(text)
            }
        }

        return "[PDF: \(name)]\n\(pages.joined(separator: "\n\n"))\n"
    }
}
