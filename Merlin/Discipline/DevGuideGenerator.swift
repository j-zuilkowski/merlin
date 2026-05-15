import Foundation

/// Regenerates mechanical sections of `docs/developer-guide.md` from the project adapter.
/// Sections are delimited by `<!-- dev-guide:begin:NAME -->` / `<!-- dev-guide:end:NAME -->`.
/// Prose outside markers is preserved. Calling generate twice is idempotent.
actor DevGuideGenerator {

    func generate(projectPath: String, adapter: ProjectAdapter) async throws {
        let docsDir = URL(fileURLWithPath: projectPath).appendingPathComponent("docs")
        try FileManager.default.createDirectory(
            at: docsDir, withIntermediateDirectories: true, attributes: nil)

        let guideURL = docsDir.appendingPathComponent("developer-guide.md")
        let sections = mechanicalSections(adapter: adapter)
        let existing = (try? String(contentsOf: guideURL, encoding: .utf8))
            ?? defaultGuideTemplate(adapter: adapter)
        let updated = replaceSections(in: existing, with: sections)
        try updated.write(to: guideURL, atomically: true, encoding: .utf8)
    }

    func mechanicalSections(adapter: ProjectAdapter) -> [String: String] {
        [
            "build": """
            ### Build

            ```bash
            \(adapter.buildCommand)
            ```
            """,
            "test": """
            ### Test

            ```bash
            \(adapter.testCommand)
            ```
            """,
            "versioning": """
            ### Versioning

            Version field: `\(adapter.versioningField)` in `\(adapter.versioningFile)`.
            """,
            "adapter": """
            ### Adapter

            Language: `\(adapter.language)`. API doc generator: `\(adapter.apiDocGenerator)`.
            Release command: `\(adapter.releaseCommand)`.
            """
        ]
    }

    private func replaceSections(
        in text: String,
        with sections: [String: String]
    ) -> String {
        var result = text
        for name in ["build", "test", "versioning", "adapter"] {
            guard let content = sections[name] else { continue }
            let begin = "<!-- dev-guide:begin:\(name) -->"
            let end = "<!-- dev-guide:end:\(name) -->"

            if let beginRange = result.range(of: begin),
               let endRange = result.range(of: end),
               beginRange.upperBound <= endRange.lowerBound {
                let replacement = begin + "\n" + content + "\n" + end
                result.replaceSubrange(beginRange.lowerBound..<endRange.upperBound,
                                       with: replacement)
            } else {
                result += "\n" + begin + "\n" + content + "\n" + end + "\n"
            }
        }
        return result
    }

    private func defaultGuideTemplate(adapter: ProjectAdapter) -> String {
        let _ = adapter
        return """
        # Developer Guide

        This guide covers the mechanics of building, testing, and releasing this project.

        """
    }
}
