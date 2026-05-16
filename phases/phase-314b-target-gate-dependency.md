# Phase 314b — TargetGateScanner Dependency-Following

## Context
Swift 5.10, macOS 14+. Working dir: ~/Documents/localProject/merlin.
Phase 314a complete: failing runtime test in `TargetGateScannerTests`.

Refines `TargetGateScanner` (phase 307b) so a target reached transitively through
`dependencies:` from a scheme-built target counts as gated. This removes the
false-positive class that blocked a real commit when the gate went live: `merlin-discipline`
is built as a dependency of `Merlin` but is named in no scheme block.

`TargetGateScanner.swift` is in `Merlin/Discipline/` — pure Foundation, compiled into
both the app and the `merlin-discipline` CLI. Keep it that way.

---

## 1. Edit: Merlin/Discipline/TargetGateScanner.swift

**1a.** Replace the entire `scan(projectPath:gatingSchemes:)` method with this version
— it builds the per-target dependency graph and expands each scheme's reach through it:

```swift
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
        let targetSet = Set(targets)

        // Each target's directly declared dependency targets.
        var directDeps: [String: Set<String>] = [:]
        for target in targets {
            let body = block(of: target, under: "targets:", in: lines)
            directDeps[target] = dependencyTargets(in: body, knownTargets: targetSet)
        }

        // For each scheme: the targets its block names directly...
        var schemesForTarget: [String: Set<String>] = [:]
        for scheme in schemes {
            let body = block(of: scheme, under: "schemes:", in: lines)
                .joined(separator: "\n")
            for target in targets where mentions(body, target) {
                schemesForTarget[target, default: []].insert(scheme)
            }
        }
        // ...plus every target reached transitively as a dependency of one it builds.
        for scheme in schemes {
            var reached: Set<String> = []
            var frontier = targets.filter {
                (schemesForTarget[$0] ?? []).contains(scheme)
            }
            while let current = frontier.popLast() {
                for dep in directDeps[current] ?? [] where !reached.contains(dep) {
                    reached.insert(dep)
                    frontier.append(dep)
                }
            }
            for dep in reached {
                schemesForTarget[dep, default: []].insert(scheme)
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
```

**1b.** Add this private helper next to the other YAML helpers:

```swift
    /// Dependency target names declared in a target's `dependencies:` block, restricted
    /// to `knownTargets` so non-target entries (`- sdk: AppIntents.framework`) are
    /// ignored.
    private func dependencyTargets(in body: [String],
                                   knownTargets: Set<String>) -> Set<String> {
        var deps: Set<String> = []
        let regex = try? NSRegularExpression(
            pattern: #"-\s*target:\s*([A-Za-z0-9_.\-]+)"#)
        for line in body {
            let ns = line as NSString
            guard let m = regex?.firstMatch(
                in: line, range: NSRange(location: 0, length: ns.length)),
                  m.numberOfRanges > 1 else { continue }
            let name = ns.substring(with: m.range(at: 1))
            if knownTargets.contains(name) { deps.insert(name) }
        }
        return deps
    }
```

`childKeys`, `block`, and `mentions` are unchanged from phase 307b — reuse them.

## 2. Edit: phases/phase-307b-target-gate-scanner.md
Add a one-line banner under that doc's title so the rebuild source of truth stays
honest:
```
> **Note:** the `scan` method here is superseded by phase 314b, which adds
> transitive `dependencies:` following. Implement 314b's version.
```

---

## Verify
```
xcodegen generate
xcodebuild -scheme MerlinTests test -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  -only-testing:MerlinTests/TargetGateScannerTests 2>&1 \
  | grep -E 'Test Case|TEST (SUCCEEDED|FAILED)|error:'
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' \
  -derivedDataPath /tmp/merlin-derived CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|warning:|BUILD (SUCCEEDED|FAILED)'
```
Expected: every `TargetGateScannerTests` method passes (including
`testDependencyOnlyTargetIsTreatedAsGated` and the original 307a tests); BUILD
SUCCEEDED, zero warnings.

## Commit
```
git add Merlin/Discipline/TargetGateScanner.swift phases/phase-307b-target-gate-scanner.md \
  phases/phase-314b-target-gate-dependency.md
git commit -m "Phase 314b — TargetGateScanner follows transitive project.yml dependencies"
```
