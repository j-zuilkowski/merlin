# Phase 148b — Two-Tier Document Verification

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 148a complete: failing tests in place.

---

## Problem

Before this phase, the CriticEngine had three silent defects that made it unfit for
document-generation verification:

1. **Truncation** — `output.prefix(4000)` meant documents longer than ~4KB were never
   fully evaluated by the reason slot.
2. **Firing condition** — the critic only fired for `highStakes` turns or when
   `classifierOverride` was set. Document-generation tasks classify as `standard`, so the
   critic never ran for them in normal operation.
3. **Generic prompt** — "say PASS or FAIL" gave the reason model no structured criteria;
   results were inconsistent and not auditable.
4. **Verdict parsing** — the verdict was read from the first PASS/FAIL occurrence in the
   response. Qwen3 and other thinking models emit a reasoning block before the final
   verdict, causing false passes/fails from preamble text.

---

## Edit: Merlin/Engine/Protocols/CriticEngineProtocol.swift

Add 4-param `evaluate` to the protocol with a backward-compatible default extension so
existing test mocks that only implement the 3-param variant require no changes.

```swift
import Foundation

protocol CriticEngineProtocol: Sendable {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message]) async -> CriticResult
    func evaluate(taskType: DomainTaskType, output: String, context: [Message], writtenFiles: [String]) async -> CriticResult
}

extension CriticEngineProtocol {
    func evaluate(taskType: DomainTaskType, output: String, context: [Message], writtenFiles: [String]) async -> CriticResult {
        await evaluate(taskType: taskType, output: output, context: context)
    }
}

extension CriticEngine: CriticEngineProtocol {}
```

---

## Edit: Merlin/Engine/CriticEngine.swift

### 3-param `evaluate` — forwards to 4-param

```swift
func evaluate(
    taskType: DomainTaskType,
    output: String,
    context: [Message]
) async -> CriticResult {
    await evaluate(taskType: taskType, output: output, context: context, writtenFiles: [])
}
```

### 4-param `evaluate` — full implementation

```swift
func evaluate(
    taskType: DomainTaskType,
    output: String,
    context: [Message],
    writtenFiles: [String]
) async -> CriticResult {
    // ... telemetry, Stage 1 unchanged ...
    // Stage 2 now receives writtenFiles
    let s2 = await runStage2(output: output, context: context, taskType: taskType, writtenFiles: writtenFiles)
    // ...
}
```

### `runStage2` — full rewrite

Key changes:
- **No truncation** — `output` passed in full; reason slot (Qwen3-27B) has 128K context
- **Written file injection** — each path is read with `String(contentsOfFile:)` and
  appended as a named block under "## Written files"
- **Structured six-criterion prompt** — completeness, factual consistency, date accuracy,
  scope adherence, internal consistency, document integrity (last criterion only when
  `writtenFiles` is non-empty)
- **Verdict from last line** — iterate `lines.reversed()` looking for PASS/FAIL prefix;
  defaults to `.pass` if no explicit verdict found (avoids false negatives on models that
  answer in prose rather than the specified format)

```swift
private func runStage2(
    output: String,
    context: [Message],
    taskType: DomainTaskType,
    writtenFiles: [String]
) async -> CriticResult? {
    guard let provider = reasonProvider else { return nil }

    let today: String = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }()

    var writtenFilesBlock = ""
    if !writtenFiles.isEmpty {
        var blocks: [String] = []
        for path in writtenFiles {
            let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? "(could not read)"
            blocks.append("### \(path)\n\(content)")
        }
        writtenFilesBlock = "\n## Written files — verify these match the stated output\n\n"
            + blocks.joined(separator: "\n\n")
    }

    let documentCriterion = !writtenFiles.isEmpty
        ? "\n6. **Document integrity** — ..."
        : ""

    let prompt = """
    You are a critic performing structured verification of AI-generated output.
    Task type: \(taskType.displayName)
    Today's date: \(today)

    ## Verification criteria
    1. **Completeness** ...
    2. **Factual consistency** ...
    3. **Date accuracy** ...
    4. **Scope adherence** ...
    5. **Internal consistency** ...\(documentCriterion)

    ## Output to verify
    \(output)
    \(writtenFilesBlock)

    ## Response format
    List your verdict on each criterion above, then end with exactly one of:
      PASS: <one-line summary>
      FAIL: <specific issue>
    The final line must start with PASS or FAIL.
    """

    // ... build request, stream provider ...

    // Parse verdict from last line
    let lines = fullResponse.components(separatedBy: .newlines)
    for line in lines.reversed() {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("PASS") { return .pass }
        if trimmed.hasPrefix("FAIL") {
            let reason = trimmed.dropFirst(4).trimmingCharacters(in: CharacterSet(charactersIn: ": "))
            return .fail(reason: String(reason))
        }
    }
    return .pass  // default: no explicit verdict → pass
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### Track written file paths

Add `var writtenFilePaths: [String] = []` at the top of `runLoop`.

In the tool dispatch loop, before `let toolStart = Date()`:

```swift
if call.function.name == "write_file" {
    let args = inputDictionary(from: call.function.arguments)
    if let path = args["path"], !path.isEmpty {
        writtenFilePaths.append(path)
    }
}
```

### Updated critic firing condition

```swift
// Before (fires for highStakes only in normal operation):
if classification.complexity != .routine,
   (classifierOverride != nil || classification.complexity == .highStakes) {

// After (also fires when write_file was called, regardless of tier):
let shouldRunCritic = classification.complexity != .routine &&
    (classifierOverride != nil ||
     classification.complexity == .highStakes ||
     !writtenFilePaths.isEmpty)
if shouldRunCritic {
```

### Pass written files to critic

```swift
let verdict = await critic.evaluate(
    taskType: taskType,
    output: fullText,
    context: context.messages,
    writtenFiles: writtenFilePaths       // ← new
)
```

---

## Create: ~/.merlin/skills/verify-document/SKILL.md

Option B — on-demand agentic verification. Runs in fork context, reason slot, high-stakes
complexity. Full tool access: reads source files to cross-reference claims, produces
structured VERIFIED / UNVERIFIABLE / CONTRADICTED report.

See full file content in the implementation commit.

Invoke: `/verify-document path/to/document.md`

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED, all 148a tests pass, zero warnings.

## Commit
```bash
git add Merlin/Engine/CriticEngine.swift \
        Merlin/Engine/AgenticEngine.swift \
        Merlin/Engine/Protocols/CriticEngineProtocol.swift
git commit -m "Phase 148b — two-tier document verification"
```
