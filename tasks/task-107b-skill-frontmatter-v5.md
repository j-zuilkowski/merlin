# Phase 107b — V5 Skill Frontmatter (role: + complexity: declarations)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 107a complete: failing skill frontmatter V5 tests in place.

---

## Edit: Merlin/Skills/SkillsRegistry.swift — add V5 frontmatter keys

Find `SkillFrontmatter` and add two optional fields:

```swift
// Add to SkillFrontmatter struct:

/// Explicit slot override — routes this skill to a specific capability slot.
/// nil = let the planner/classifier decide.
var role: AgentSlot? = nil

/// Explicit complexity override — bypasses the classifier for this skill.
/// nil = let the classifier decide.
var complexity: ComplexityTier? = nil
```

In the frontmatter parser (wherever YAML/TOML-style key-value pairs are parsed), add:

```swift
// After existing key parsing:
if let roleStr = dict["role"] as? String {
    frontmatter.role = AgentSlot(rawValue: roleStr)
}
if let complexityStr = dict["complexity"] as? String {
    frontmatter.complexity = ComplexityTier(rawValue: complexityStr)
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift — invokeSkill respects declarations

```swift
// BEFORE:
func invokeSkill(_ skill: Skill, arguments: String = "") -> AsyncStream<AgentEvent> {
    let body = skillsRegistry?.render(skill: skill, arguments: arguments)
        ?? SkillsRegistry.renderStatic(skill: skill, arguments: arguments)

    if skill.frontmatter.context == "fork" {
        return runFork(prompt: body)
    }

    return send(userMessage: body)
}

// AFTER:
func invokeSkill(_ skill: Skill, arguments: String = "") -> AsyncStream<AgentEvent> {
    let body = skillsRegistry?.render(skill: skill, arguments: arguments)
        ?? SkillsRegistry.renderStatic(skill: skill, arguments: arguments)

    if skill.frontmatter.context == "fork" {
        return runFork(prompt: body)
    }

    // Apply V5 frontmatter overrides — prefix the message with the appropriate annotations
    // so the planner classifier and slot router pick them up.
    var message = body
    if let role = skill.frontmatter.role {
        message = "@\(role.rawValue) \(message)"
    }
    if let complexity = skill.frontmatter.complexity {
        message = "#\(complexity.rawValue) \(message)"
    }

    return send(userMessage: message)
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'SkillFrontmatterV5.*passed|SkillFrontmatterV5.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED; SkillFrontmatterV5Tests → 6 pass; all prior tests pass; zero warnings.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/Skills/SkillsRegistry.swift \
        Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 107b — Skill frontmatter role: and complexity: declarations"
```
