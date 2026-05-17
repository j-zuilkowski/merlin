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
/// phases. This scanner makes that condition a first-class discipline finding.
actor TargetGateScanner {

    /// Reports targets declared in `project.yml` that no scheme builds, or — when
    /// `gatingSchemes` is non-empty — that only non-gating schemes build.
    /// Returns `[]` when there is no `project.yml` (self-gates to xcodegen projects).
    func scan(projectPath: String,
              gatingSchemes: [String] = []) async -> [UngatedTargetFinding] {
        let ymlURL = URL(fileURLWithPath: projectPath)
            .appendingPathComponent("project.yml")
        // Self-gates to xcodegen projects; check existence first so a project with no
        // project.yml never constructs an NSError.
        guard FileManager.default.fileExists(atPath: ymlURL.path),
              let text = try? String(contentsOf: ymlURL, encoding: .utf8) else {
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

    // MARK: - Minimal YAML helpers (xcodegen project.yml structure)

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

    /// The indent-2 keys directly under a column-0 `section` line (e.g. `targets:`).
    private func childKeys(of section: String, in lines: [String]) -> [String] {
        guard let start = lines.firstIndex(of: section) else { return [] }
        var keys: [String] = []
        var i = start + 1
        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty && !line.hasPrefix(" ") { break }
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
                return []
            }
            i += 1
        }
        guard i < lines.count else { return [] }
        var body: [String] = []
        i += 1
        while i < lines.count {
            let line = lines[i]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { i += 1; continue }
            guard line.hasPrefix("   ") else { break }
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
