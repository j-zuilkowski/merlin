# Task 251a — DocReferenceGraph Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 250b complete: ManualBaselineManager + ManualSectionTemplateWriter live.

Replaces the `DocReferenceGraph` stub with a real implementation using automatic mode:
greps doc files for symbol-shaped strings, cross-checks against the code symbol index.

New surface introduced in task 251b (replacing stub):
  - `DocReferenceGraph.build(projectPath:) async -> [DocReference]` — real implementation.
  - `DocReferenceGraph.staleReferences(against changedSymbols:) async -> [DocReference]`
    — returns references whose `codeSymbol` appears in `changedSymbols`.
  - Automatic mode heuristic: scan `.md` files for PascalCase, camelCase, and snake_case
    identifiers that also appear in `.swift` / `.rs` source files.

TDD coverage:
  File 1 — `MerlinTests/Unit/DocReferenceGraphTests.swift`:
    A doc file that mentions `ProviderBudget` when a Swift source defines `ProviderBudget`
    produces a `DocReference`; a doc that mentions `NonExistentSymbol` not found in source
    produces no reference; `staleReferences(against:["ProviderBudget"])` returns the reference;
    `staleReferences(against:["OtherThing"])` does not.

---

## Write to

- `MerlinTests/Unit/DocReferenceGraphTests.swift`

### MerlinTests/Unit/DocReferenceGraphTests.swift

```swift
import XCTest
@testable import Merlin

final class DocReferenceGraphTests: XCTestCase {

    private func makeTmpProject() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drg-\(UUID())")
        let srcDir = dir.appendingPathComponent("Src")
        let docDir = dir.appendingPathComponent("docs")
        try FileManager.default.createDirectory(at: srcDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: docDir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - build produces reference when doc mentions source symbol

    func testBuildProducesReferenceForKnownSymbol() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try """
        import Foundation
        struct ProviderBudget: Sendable {
            let maxInputTokens: Int
        }
        """.write(to: proj.appendingPathComponent("Src/ProviderBudget.swift"),
                  atomically: true, encoding: .utf8)

        try """
        # Architecture

        `ProviderBudget` controls how many tokens each provider can receive.
        """.write(to: proj.appendingPathComponent("docs/spec.md"),
                  atomically: true, encoding: .utf8)

        let graph = DocReferenceGraph()
        let refs = await graph.build(projectPath: proj.path)
        let match = refs.first { $0.codeSymbol == "ProviderBudget" }
        XCTAssertNotNil(match, "Expected reference for ProviderBudget")
        XCTAssertTrue(match?.docFile.hasSuffix("spec.md") == true)
    }

    // MARK: - build does not produce reference for unknown symbol

    func testBuildNoReferenceForUnknownSymbol() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        // No source file defines NonExistentSymbol
        try """
        # Architecture

        `NonExistentSymbol` is mentioned here but does not exist in source.
        """.write(to: proj.appendingPathComponent("docs/spec.md"),
                  atomically: true, encoding: .utf8)

        let graph = DocReferenceGraph()
        let refs = await graph.build(projectPath: proj.path)
        let match = refs.first { $0.codeSymbol == "NonExistentSymbol" }
        XCTAssertNil(match, "Should not produce reference for unknown symbol")
    }

    // MARK: - staleReferences

    func testStaleReferencesMatchesChangedSymbol() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try "struct ProviderBudget {}".write(
            to: proj.appendingPathComponent("Src/PB.swift"),
            atomically: true, encoding: .utf8)
        try "# Doc\n\n`ProviderBudget` is used here.".write(
            to: proj.appendingPathComponent("docs/guide.md"),
            atomically: true, encoding: .utf8)

        let graph = DocReferenceGraph()
        _ = await graph.build(projectPath: proj.path)
        let stale = await graph.staleReferences(against: ["ProviderBudget"])
        XCTAssertFalse(stale.isEmpty, "ProviderBudget should appear as stale")
    }

    func testStaleReferencesIgnoresUnrelatedSymbol() async throws {
        let proj = try makeTmpProject()
        defer { try? FileManager.default.removeItem(at: proj) }

        try "struct ProviderBudget {}".write(
            to: proj.appendingPathComponent("Src/PB.swift"),
            atomically: true, encoding: .utf8)
        try "# Doc\n\n`ProviderBudget` is here.".write(
            to: proj.appendingPathComponent("docs/guide.md"),
            atomically: true, encoding: .utf8)

        let graph = DocReferenceGraph()
        _ = await graph.build(projectPath: proj.path)
        let stale = await graph.staleReferences(against: ["SomeOtherThing"])
        XCTAssertTrue(stale.isEmpty, "No stale refs for unrelated symbol")
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
```

Expected: **BUILD FAILED** because the stub `DocReferenceGraph.build` returns `[]` and
`staleReferences` similarly — the tests expecting real results will fail at runtime (tests
compile but fail), or the real `build(projectPath:)` signature change causes compile errors.

## Commit

```bash
git add tasks/task-251a-doc-reference-graph-tests.md \
    MerlinTests/Unit/DocReferenceGraphTests.swift
git commit -m "Task 251a — DocReferenceGraphTests (failing)"
```
