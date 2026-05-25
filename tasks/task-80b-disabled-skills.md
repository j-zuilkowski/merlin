# Phase 80b — DisabledSkillNames Enforcement Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 80a complete: failing DisabledSkillsTests in place.

---

## Edit: Merlin/Skills/SkillsRegistry.swift

Add a method after `skill(named:)`:

```swift
    func enabledSkills(from skills: [Skill], disabledNames: [String]) -> [Skill] {
        skills.filter { !disabledNames.contains($0.name) }
    }
```

Also add a convenience that reads from `AppSettings`:

```swift
    var enabledSkills: [Skill] {
        enabledSkills(from: skills, disabledNames: AppSettings.shared.disabledSkillNames)
    }
```

---

## Edit: Merlin/Engine/ContextManager.swift

The existing `buildSkillReinjectionBlock` takes `[Skill]`. Add an overload that accepts a
`disabledNames` parameter:

```swift
    func buildSkillReinjectionBlock(skills: [Skill], disabledNames: [String]) -> String {
        let filtered = skills.filter { !disabledNames.contains($0.name) }
        return buildSkillReinjectionBlock(skills: filtered)
    }
```

If `buildSkillReinjectionBlock(skills:)` is already the only form, rename it to accept an
optional disabledNames and keep backward compatibility:

```swift
    func buildSkillReinjectionBlock(skills: [Skill], disabledNames: [String] = []) -> String {
        let visible = disabledNames.isEmpty ? skills : skills.filter { !disabledNames.contains($0.name) }
        // existing body using `visible` instead of `skills`
        ...
    }
```

Update the call site inside `ContextManager` where `buildSkillReinjectionBlock` is called
post-compaction to pass `AppSettings.shared.disabledSkillNames`:

```swift
    let block = buildSkillReinjectionBlock(
        skills: recentlyInvokedSkills,
        disabledNames: AppSettings.shared.disabledSkillNames
    )
```

---

## Edit: Merlin/Sessions/LiveSession.swift

Ensure that when the session wires skills into the engine, it passes enabled skills only.
Find where `appState.engine.skillsRegistry` is set and ensure the registry's `enabledSkills`
property is used wherever the skill list is passed to the context or reinjection logic.

No immediate change needed here if `ContextManager` already reads from `skillsRegistry.skills` —
the `buildSkillReinjectionBlock` call sites that receive a `[Skill]` array should pass
`skillsRegistry.enabledSkills` instead of `skillsRegistry.skills`.

Search for all call sites of `buildSkillReinjectionBlock` in the project and update them:

```bash
grep -rn "buildSkillReinjectionBlock" ~/Documents/localProject/merlin/Merlin/
```

For each call site that passes `skillsRegistry.skills`, change to `skillsRegistry.enabledSkills`.

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'DisabledSkills.*passed|DisabledSkills.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD SUCCEEDED`; all DisabledSkillsTests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Skills/SkillsRegistry.swift \
        Merlin/Engine/ContextManager.swift \
        Merlin/Sessions/LiveSession.swift
git commit -m "Phase 80b — enforce AppSettings.disabledSkillNames in SkillsRegistry + ContextManager"
```
