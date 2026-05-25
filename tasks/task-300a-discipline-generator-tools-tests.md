# Phase 300a — Discipline Generator Tools Tests (failing)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Unit D1 of the wiring plan. Phases 294–299 complete.

`APIDocGenerator`, `DevGuideGenerator`, `ValeStyleWriter`, `ManualSectionTemplateWriter`
generate files but have no trigger. D1 registers them as agent-callable tools so the
agent and the `project:*` skills can invoke them and the results are observable as tool
output.

New surface in phase 300b:
  - Four `ToolDefinition`s in `ToolDefinitions` and four handlers registered on the
    `ToolRouter` (in `AppState.registerAllTools` / the builtin path):
    `generate_api_docs`, `generate_dev_guide`, `write_vale_styles`,
    `scaffold_manual_coverage`.

TDD coverage:
  `MerlinTests/Unit/DisciplineGeneratorToolsTests.swift` — after builtin tool
  registration, `ToolRegistry.shared` exposes the four discipline tool names.

## Write to: MerlinTests/Unit/DisciplineGeneratorToolsTests.swift

```swift
import XCTest
@testable import Merlin

/// Phase 300a — failing tests for discipline generator tools.
@MainActor
final class DisciplineGeneratorToolsTests: XCTestCase {

    func testDisciplineGeneratorToolsAreRegistered() {
        ToolRegistry.shared.registerBuiltins()
        let expected = ["generate_api_docs", "generate_dev_guide",
                        "write_vale_styles", "scaffold_manual_coverage"]
        for name in expected {
            XCTAssertTrue(ToolRegistry.shared.contains(named: name),
                          "discipline tool '\(name)' must be registered")
        }
    }
}
```

NOTE for executor: `ToolRegistry` may expose presence differently (e.g. a `tools`
collection or a `definition(named:)` lookup). Match the real query API used by existing
builtin-tool tests; the assertion's intent is "these four tool names are registered".

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/DisciplineGeneratorToolsTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
```
Expected: BUILD SUCCEEDED; `testDisciplineGeneratorToolsAreRegistered` FAILS. This is a
runtime-failure phase — the test compiles fine against the real `ToolRegistry` query
API and fails because the four discipline tools are not registered yet (300b registers
them). It must be verified with `test`, not `build-for-testing`, so the test actually
runs.

## Commit
```
git add MerlinTests/Unit/DisciplineGeneratorToolsTests.swift tasks/task-300a-discipline-generator-tools-tests.md
git commit -m "Phase 300a — Discipline generator tools tests (failing)"
```
