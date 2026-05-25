# Task 307b — TargetGateScanner (implementation)

> **Note:** the `scan` method here is superseded by task 314b, which adds
> transitive `dependencies:` following. Implement 314b's version.

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Task 307a complete: failing tests in `TargetGateScannerTests`.

`TargetGateScanner` reads `project.yml`, finds targets the build gate never compiles,
and feeds `ungatedTarget` findings into the discipline queue. Pure Foundation — the file
lands in `Merlin/Discipline/`, which is compiled into **both** the `Merlin` app target
and the `merlin-discipline` CLI target, so it must not import SwiftUI/AppKit.

---

## 1. Write to: Merlin/Discipline/TargetGateScanner.swift

```swift
import Foundation

/// One target that the build gate never compiles.
struct UngatedTargetFinding: Sendable, Equatable {
    let targetName: String
    let reason: String
    /// True when the target is built by no scheme at all (hard problem); false when it
    /// is built only by schemes outside the gating set (advisory).
    let blocking: Bool
}

/// Scans `project.yml` for targets the verification gate never builds.
///
/// A target the gate never compiles rots silently the moment an API it depends on
/// changes — exactly how `MerlinLiveTests` / `MerlinE2ETests` bit-rotted for ~160
///  tasks. This scanner makes that condition a first-class discipline finding.
actor TargetGateScanner {

    /// Reports targets declared in `project.yml` that no scheme builds, or — when
    /// `gatingSchemes` is non-empty — that only non-gating schemes build.
    /// Returns `[]` when there is no `project.yml` (self-gates to xcodegen projects).
    func scan(projectPath: String,
              gatingSchemes: [String] = []) async -> [UngatedTargetFinding] {
        let ymlURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent("project.yml")
        guard let text = try? String(contentsOf: ymlURL, encoding: .utf8) else {
            return []
        }
        let lines = text.components(separatedBy: .newlines)

        let targets = childKeys(of: "targets:", in: lines)
        let schemes = childKeys(of: "schemes:", in: lines)
        guard !targets.isEmpty else { return [] }

        // For each scheme, the set of targets its block references by name.
        var schemesForTarget: [String: Set<String>] = [:]
        for scheme in schemes {
            let body = block(of: scheme, under: "schemes:", in: lines)
                .joined(separator: "\n")
            for target in targets where mentions(body, target) {
                schemesForTarget[target, default: []].insert(scheme)
            }
        }

        let gating = Set(gatingSchemes)
        var findings: [UngatedTargetFinding] = []
        for target in targets.sorted() {
            let builtBy = schemesForTarget[target] ?? []
            if builtBy.isEmpty {
                findings.append(UngatedTargetFinding(
                    targetName: target,
                    reason: "Target is built by no scheme — it will rot uncompiled.",
                    blocking: true))
            } else if !gating.isEmpty && builtBy.isDisjoint(with: gating) {
                let names = builtBy.sorted().joined(separator: ", ")
                findings.append(UngatedTargetFinding(
                    targetName: target,
                    reason: "Target is built only by non-gating scheme(s): \(names) — "
                        + "not exercised by the verification gate.",
                    blocking: false))
            }
        }
        return findings
    }

    // MARK: - Minimal YAML helpers (xcodegen project.yml structure)

    /// The indent-2 keys directly under a column-0 `section` line (e.g. `targets:`).
    private func childKeys(of section: String, in lines: [String]) -> [String] {
        guard let start = lines.firstIndex(of: section) else { return [] }
        var keys: [String] = []
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !line.hasPrefix(" ") { break }   // next column-0 key
            if line.hasPrefix("  ") && !line.hasPrefix("   "),
               !trimmed.hasPrefix("#"), trimmed.hasSuffix(":") {
                keys.append(String(trimmed.dropLast()))
            }
            i += 1
        }
        return keys
    }

    /// All lines nested beneath the indent-2 key `key` under column-0 `section`.
    private func block(of key: String, under section: String,
                       in lines: [String]) -> [String] {
        guard let secStart = lines.firstIndex(of: section) else { return [] }
        let keyLine = "  \(key):"
        var i = secStart + 1
        while i < lines.count && lines[i] != keyLine {
            let line = lines[i]
            if !line.trimmingCharacters(in: .whitespaces).isEmpty,
               !line.hasPrefix(" ") {
                return []   // left the section without finding the key
            }
            i += 1
        }
        guard i < lines.count else { return [] }
        var body: [String] = []
        i += 1
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
            guard line.hasPrefix("   ") else { break }   // dedented out of the block
            body.append(line)
            i += 1
        }
        return body
    }

    /// True when `target` appears as a whole word anywhere in `body`. The character
    /// class excludes `-` so hyphenated target names (`merlin-discipline`) match
    /// exactly and `Merlin` does not falsely match inside `MerlinTests`.
    private func mentions(_ body: String, _ target: String) -> Bool {
        let pattern = "(^|[^A-Za-z0-9_-])"
            + NSRegularExpression.escapedPattern(for: target)
            + "([^A-Za-z0-9_-]|$)"
        return body.range(of: pattern, options: .regularExpression) != nil
    }
}
```

## 2. Edit: Merlin/Discipline/Finding.swift
Add one case to `FindingCategory`:
```swift
enum FindingCategory: String, Codable, Sendable, CaseIterable {
    case taskDrift
    case manualCoverageGap
    case docStaleReference
    case whyCommentMissing
    case proseReadabilityFail
    case overrideAuditAccumulation
    case ungatedTarget
}
```
**Then update `MerlinTests/Unit/FindingModelTests.swift`** — it carries one rawValue
assertion per `FindingCategory` case. Add
`XCTAssertEqual(FindingCategory.ungatedTarget.rawValue, "ungatedTarget")` alongside the
others, and adjust any `FindingCategory.allCases.count` assertion to the new total.
(Skipping this is the addition-gap bug class — the test target would fail to match.)

## 3. Edit: Merlin/Discipline/DisciplineEngine.swift

**3a. New stored property** — next to the other scanners:
```swift
private let targetGateScanner: TargetGateScanner
```

**3b. New init parameter** — insert after `proseReadabilityChecker:` and before
`storePath:`, **with a default value** so every existing `DisciplineEngine(...)` call
site (e.g. `PendingAttentionChipCountTests`, `DisciplineEngineTests`, `AppState`)
continues to compile unchanged. Do NOT modify any other call site.
```swift
        proseReadabilityChecker: ProseReadabilityChecker,
        targetGateScanner: TargetGateScanner = TargetGateScanner(),
        storePath: String,
```
And in the init body: `self.targetGateScanner = targetGateScanner`.

**3c. In `scan(projectPath:)`** — add a fifth parallel scan alongside the existing
`async let` block:
```swift
async let ungatedTargets = targetGateScanner.scan(
    projectPath: projectPath,
    gatingSchemes: Self.gatingSchemes(projectPath: projectPath))
```
Extend the tuple await to include it:
```swift
let (drift, gaps, refs, why, ungated) = await (
    driftFindings, coverageGaps, docRefs, whyTriggers, ungatedTargets)
```

**3d. Conversion block** — after the WHY-comment block, before the prose block:
```swift
// Ungated targets — a target the build gate never compiles.
for ut in ungated {
    let f = Finding(
        id: UUID(),
        category: .ungatedTarget,
        severity: ut.blocking ? .block : .nudge,
        summary: ut.targetName,
        detail: ut.reason,
        suggestedAction: "Add the target to a verification scheme, or list its "
            + "scheme in .merlin/project.toml gating_schemes.",
        createdAt: now,
        lastSeenAt: now)
    await queue.add(f)
    findings.append(f)
}
```

**3e. New static helper** — in the `Doc-file helpers` MARK section:
```swift
/// Verification-gate scheme names, read from `.merlin/project.toml`'s
/// `gating_schemes = ["A", "B"]` line. Empty when the file or key is absent.
static func gatingSchemes(projectPath: String) -> [String] {
    let tomlURL = URL(fileURLWithPath: projectPath)
        .appendingPathComponent(".merlin/project.toml")
    guard let text = try? String(contentsOf: tomlURL, encoding: .utf8) else {
        return []
    }
    for line in text.components(separatedBy: .newlines) {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.hasPrefix("gating_schemes"),
              let open = t.firstIndex(of: "["),
              let close = t.lastIndex(of: "]") else { continue }
        return t[t.index(after: open)..<close]
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) }
            .filter { !$0.isEmpty }
    }
    return []
}
```

## 4. Create: .merlin/project.toml  (in the merlin repo root)
Adopt Merlin into its own discipline system and declare the verification gate. Match the
exact key names `ProjectConfigLoader` expects — read `Merlin/Discipline/ProjectConfigLoader.swift`
to confirm — then add the `gating_schemes` line (read only by `TargetGateScanner`):
```toml
adapter = "swift-xcode"
adapter_version = "1.0"
discipline_layers = ["soft_prompt", "pre_commit"]
manual_coverage_baseline = 0
decay_per_release = 0
gating_schemes = ["MerlinTests"]
```
`MerlinTests-Live` is intentionally absent — it is not yet a gating scheme. Task 312
adds it once the live scheme is folded into the build gate. Until then, a discipline
scan of the Merlin repo will correctly flag `MerlinLiveTests`, `MerlinE2ETests`, and
`TestTargetApp` as ungated.

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/TargetGateScannerTests -only-testing:MerlinTests/FindingModelTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: `TargetGateScannerTests` and `FindingModelTests` pass; BUILD SUCCEEDED, zero
warnings.

## Commit
```
git add Merlin/Discipline/TargetGateScanner.swift Merlin/Discipline/Finding.swift \
  Merlin/Discipline/DisciplineEngine.swift MerlinTests/Unit/FindingModelTests.swift \
  .merlin/project.toml tasks/task-307b-target-gate-scanner.md
git commit -m "Task 307b — TargetGateScanner: flag targets the build gate never compiles"
```
