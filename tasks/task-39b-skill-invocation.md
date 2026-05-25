# Phase 39b — Skill Invocation + Built-in Skills

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 39a complete: failing SkillInvocationTests in place.

---

## Modify: Merlin/Engine/AgenticEngine.swift

Add a `skillsRegistry: SkillsRegistry?` property and two new methods:

```swift
var skillsRegistry: SkillsRegistry?

/// Invoke a skill: render its body, inject as a user turn, stream response.
func invokeSkill(_ skill: Skill, arguments: String = "") -> AsyncStream<AgentEvent> {
    let body = skillsRegistry?.render(skill: skill, arguments: arguments)
              ?? SkillsRegistry.renderStatic(skill: skill, arguments: arguments)

    if skill.frontmatter.context == "fork" {
        return runFork(prompt: body)
    }

    return send(userMessage: body)
}

/// Run in an isolated context — result is streamed but not added to session history.
private func runFork(prompt: String) -> AsyncStream<AgentEvent> {
    AsyncStream { continuation in
        isRunning = true
        let forkContext = ContextManager()
        let task = Task { @MainActor in
            defer { self.isRunning = false; self.currentTask = nil }
            do {
                try await self.runLoop(
                    userMessage: prompt,
                    continuation: continuation,
                    contextOverride: forkContext
                )
                continuation.finish()
            } catch is CancellationError {
                continuation.yield(.systemNote("[Interrupted]"))
                continuation.finish()
            } catch {
                continuation.yield(.error(error))
                continuation.finish()
            }
        }
        self.currentTask = task
    }
}
```

Update `runLoop(userMessage:continuation:)` to accept an optional `contextOverride`:

```swift
private func runLoop(
    userMessage: String,
    continuation: AsyncStream<AgentEvent>.Continuation,
    contextOverride: ContextManager? = nil
) async throws { ... }
```

When `contextOverride` is provided, use it instead of `self.contextManager` for all
read/write operations in this call. The session's own `contextManager` is untouched.

---

## Write to: Merlin/Skills/Builtin/ (8 files)

Create one SKILL.md per built-in skill. These are embedded as regular source-adjacent
resources loaded at app startup by copying them into `~/.merlin/skills/` if not already
present (or always load from the bundle path via `Bundle.main.resourceURL`).

### Merlin/Skills/Builtin/review/SKILL.md
```
---
name: review
description: Code review of staged changes — quality, correctness, security
user-invocable: true
---

Review the staged changes in this session for code quality, correctness, and security issues.
For each file, list specific issues found (if any) and suggest concrete improvements.
Format your response as a bulleted list grouped by file. If a file looks good, say so briefly.
```

### Merlin/Skills/Builtin/plan/SKILL.md
```
---
name: plan
description: Switch to plan mode and map out a task before touching any files
user-invocable: true
disable-model-invocation: true
---

Switch this session to Plan mode. In Plan mode you must not write, create, delete, or move
files, and must not run shell commands. Read files as needed to understand the current state,
then produce a numbered implementation plan. Present the plan clearly so I can review and
edit it before approving execution.
```

### Merlin/Skills/Builtin/commit/SKILL.md
```
---
name: commit
description: Generate a commit message from the current staged diff
user-invocable: true
disable-model-invocation: true
allowed-tools: Bash(git diff --staged)
---

Run `git diff --staged` to get the current staged diff, then write a concise commit message
following this format:
- Subject line: imperative mood, ≤72 characters, no trailing period
- Blank line
- Body: 1–3 sentences explaining *why* (not what) if non-obvious
Do not include "Co-authored-by" lines unless I ask.
```

### Merlin/Skills/Builtin/test/SKILL.md
```
---
name: test
description: Write tests for a function, type, or module
user-invocable: true
argument-hint: [function or module name]
---

Write thorough unit tests for $ARGUMENTS following the project's TDD conventions:
- Use XCTest
- Cover happy path, edge cases, and error paths
- No mocks unless the dependency is external I/O
- Tests must compile and fail before the implementation exists
```

### Merlin/Skills/Builtin/explain/SKILL.md
```
---
name: explain
description: Explain selected code in plain English
user-invocable: true
argument-hint: [file or function name]
---

Explain $ARGUMENTS in plain English. Cover:
1. What it does at a high level
2. Key design decisions or non-obvious behaviours
3. How it fits into the surrounding system
Keep it concise — avoid restating what the code already makes obvious.
```

### Merlin/Skills/Builtin/debug/SKILL.md
```
---
name: debug
description: Structured debugging session — reproduce, isolate, diagnose, fix
user-invocable: true
argument-hint: [error message or test name]
---

Debug $ARGUMENTS using this process:
1. Reproduce — confirm the failure is consistent
2. Isolate — narrow to the smallest failing case
3. Diagnose — identify root cause, not just symptoms
4. Fix — implement the minimal correct change
5. Verify — confirm the fix passes and no regressions introduced
```

### Merlin/Skills/Builtin/refactor/SKILL.md
```
---
name: refactor
description: Propose a focused refactor for a code section
user-invocable: true
argument-hint: [file or type name]
---

Propose a refactor for $ARGUMENTS. Rules:
- Preserve all existing behaviour (no feature changes)
- Reduce complexity or duplication — do not introduce new abstractions unless clearly warranted
- Explain the motivation for each structural change
- Present a diff or before/after for the key changes
```

### Merlin/Skills/Builtin/summarise/SKILL.md
```
---
name: summarise
description: Summarise the current session — what was done and what is next
user-invocable: true
disable-model-invocation: true
context: fork
---

Summarise this session concisely:
1. **What was accomplished** — bullet list of concrete changes made
2. **Key decisions** — any non-obvious design choices
3. **Outstanding items** — what remains or was deferred
Keep the whole summary under 200 words.
```

---

## Modify: Merlin/Sessions/LiveSession.swift

Wire `skillsRegistry` into the engine:

```swift
init(projectRef: ProjectRef) {
    // ... existing init
    self.appState.engine.skillsRegistry = self.skillsRegistry
}
```

---

## Modify: Merlin/App/ToolRegistration.swift (or AppState.swift)

At app startup, copy built-in skills to `~/.merlin/skills/` if they don't already exist there,
so users can customise them:

```swift
static func installBuiltinSkills() {
    guard let resourceURL = Bundle.main.resourceURL?
        .appendingPathComponent("Builtin") else { return }
    let dest = URL(fileURLWithPath: "\(ProcessInfo.processInfo.environment["HOME"] ?? "")")
        .appendingPathComponent(".merlin/skills")
    let fm = FileManager.default
    guard let skills = try? fm.contentsOfDirectory(at: resourceURL,
                                                   includingPropertiesForKeys: nil) else { return }
    for skillDir in skills {
        let target = dest.appendingPathComponent(skillDir.lastPathComponent)
        guard !fm.fileExists(atPath: target.path) else { continue }
        try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
        try? fm.copyItem(at: skillDir, to: target)
    }
}
```

Call `installBuiltinSkills()` from `AppState.init`.

Also add `Merlin/Skills/Builtin/` as a `Copy Bundle Resources` build phase entry in project.yml.

---

## Modify: project.yml

Add bundle resources for built-in skills and update Merlin target sources.

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `SkillInvocationTests` → 4 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Engine/AgenticEngine.swift \
        Merlin/Sessions/LiveSession.swift \
        Merlin/App/ToolRegistration.swift \
        "Merlin/Skills/Builtin/" \
        project.yml
git commit -m "Phase 39b — skill invocation + fork context + built-in skills"
```
