# Task 253b — DevGuideGenerator

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 253a complete: failing tests for DevGuideGenerator.

---

## Write to

### Merlin/Discipline/DevGuideGenerator.swift (new file)

```swift
import Foundation

/// Regenerates mechanical sections of `docs/developer-guide.md` from the project adapter.
/// Sections are delimited by `<!-- dev-guide:begin:NAME -->` / `<!-- dev-guide:end:NAME -->`.
/// Prose outside markers is preserved. Calling generate twice is idempotent.
actor DevGuideGenerator {

    // MARK: - API

    func generate(projectPath: String, adapter: ProjectAdapter) async throws {
        let docsDir = URL(fileURLWithPath: projectPath).appendingPathComponent("docs")
        try FileManager.default.createDirectory(
            at: docsDir, withIntermediateDirectories: true, attributes: nil)
        let guideURL = docsDir.appendingPathComponent("developer-guide.md")

        let sections = await mechanicalSections(adapter: adapter)
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

    // MARK: - Section replacement

    private func replaceSections(
        in text: String,
        with sections: [String: String]
    ) -> String {
        var result = text
        for (name, content) in sections {
            let begin = "<!-- dev-guide:begin:\(name) -->"
            let end = "<!-- dev-guide:end:\(name) -->"

            if let beginRange = result.range(of: begin),
               let endRange = result.range(of: end),
               beginRange.upperBound <= endRange.lowerBound {
                let replacement = begin + "\n" + content + "\n" + end
                result.replaceSubrange(beginRange.lowerBound..<endRange.upperBound,
                                       with: replacement)
            } else {
                // Append new section at the end
                result += "\n" + begin + "\n" + content + "\n" + end + "\n"
            }
        }
        return result
    }

    // MARK: - Default template

    private func defaultGuideTemplate(adapter: ProjectAdapter) -> String {
        """
        # Developer Guide

        This guide covers the mechanics of building, testing, and releasing this project.

        """
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** and all task 253a tests pass. No prior task regresses.

## Commit

```bash
git add tasks/task-253b-devguide-generator.md \
    Merlin/Discipline/DevGuideGenerator.swift
git commit -m "Task 253b — DevGuideGenerator mechanical-section generator"
```
