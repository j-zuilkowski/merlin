# Task 300b — Discipline Generator Tools (implementation)

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 300a complete: failing test in `DisciplineGeneratorToolsTests`. Unit D1 of the plan.

## Edit: Merlin/Tools/ToolDefinitions.swift
Add four `ToolDefinition`s in the existing OpenAI function-calling format (match the
shape of `readFile`, `runShell`, etc.):
- `generateAPIDocs` — name `generate_api_docs`, no required params (optional `projectPath`).
- `generateDevGuide` — name `generate_dev_guide`, optional `projectPath`.
- `writeValeStyles` — name `write_vale_styles`, optional `projectPath`.
- `scaffoldManualCoverage` — name `scaffold_manual_coverage`, optional `projectPath`.
Include them wherever the builtin definitions are aggregated for registration.

## Edit: Merlin/App/AppState.swift
In the tool-handler registration block (where `run_shell` and the other builtins are
registered on `toolRouter`), register four handlers. Each resolves the adapter and calls
the generator; the returned string is the tool result (observable as tool output):

```swift
toolRouter.register(name: "generate_api_docs") { _ in
    let path = engine.currentProjectPath ?? projectPath
    let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: path)
    let out = try await APIDocGenerator().generate(projectPath: path, adapter: adapter)
    return "API docs generated: \(out)"
}
toolRouter.register(name: "generate_dev_guide") { _ in
    let path = engine.currentProjectPath ?? projectPath
    let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: path)
    try await DevGuideGenerator().generate(projectPath: path, adapter: adapter)
    return "Developer guide updated."
}
toolRouter.register(name: "write_vale_styles") { _ in
    let path = engine.currentProjectPath ?? projectPath
    try await ValeStyleWriter().writeStyles(to: path + "/.vale/styles")
    return "Vale styles written to .vale/styles."
}
toolRouter.register(name: "scaffold_manual_coverage") { _ in
    let path = engine.currentProjectPath ?? projectPath
    let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: path)
    let gaps = await ManualCoverageScanner().scan(projectPath: path, adapter: adapter)
    let writer = ManualSectionTemplateWriter()
    for gap in gaps {
        try await writer.write(gap: gap, to: path + "/docs/manual-coverage.md")
    }
    return "Scaffolded \(gaps.count) manual-coverage section(s)."
}
```
Adjust signatures to the generators' actual APIs (`Merlin/Discipline/*Generator.swift`,
`ValeStyleWriter.swift`, `ManualSectionTemplateWriter.swift`). Ensure
`ToolRegistry.shared.registerBuiltins()` registers the four new definitions.

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -only-testing:MerlinTests/DisciplineGeneratorToolsTests
```
Expected: BUILD SUCCEEDED, test passes.

Runtime check: in the app, ask the agent to "generate API docs" / "write Vale styles" and
confirm the tool runs and its result appears as a tool-call row.

## Commit
```
git add Merlin/Tools/ToolDefinitions.swift Merlin/App/AppState.swift \
  tasks/task-300b-discipline-generator-tools.md
git commit -m "Task 300b — Discipline generator tools"
```
