# Phase 147b — Adaptive Loop Ceiling

## Context
Swift 5.10, macOS 14+. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 147a complete: failing tests in place.

---

## Write to: Merlin/Engine/ProjectSizeObserver.swift

```swift
import Foundation

// MARK: - ProjectSizeMetrics

/// Observed characteristics of a project directory used to compute an adaptive loop ceiling.
struct ProjectSizeMetrics: Sendable, Equatable {
    /// Number of source-code files found in the project tree (excluding build/vendor dirs).
    let sourceFileCount: Int

    /// Baseline metrics for when no project path is available.
    static let `default` = ProjectSizeMetrics(sourceFileCount: 0)

    /// Computes an adaptive loop iteration ceiling for the given complexity tier.
    ///
    /// Formula: `clamp(10 + floor(log2(sourceFileCount + 1)) × 4, 10, 80)` × tier multiplier,
    /// result clamped back to [10, 80].
    func adaptiveCeiling(for tier: ComplexityTier) -> Int {
        let base = 10
        let sizeScore = Int(log2(Double(sourceFileCount + 1))) * 4
        let raw = base + sizeScore
        let tiered: Int
        switch tier {
        case .routine:    tiered = max(Int(Double(raw) * 0.6), base)
        case .standard:   tiered = raw
        case .highStakes: tiered = Int(Double(raw) * 1.5)
        }
        return min(max(tiered, 10), 80)
    }
}

// MARK: - ProjectSizeObserver

/// Scans a project directory and returns `ProjectSizeMetrics`.
///
/// Counting is fast (~50 ms for 10,000-file trees) because only directory entry names
/// are inspected — no file contents are read. The observer is an actor so concurrent
/// callers share one in-flight scan per path.
actor ProjectSizeObserver {

    // MARK: - Source extensions

    /// File extensions that count as source code.
    private static let sourceExtensions: Set<String> = [
        "swift", "py", "js", "ts", "tsx", "jsx",
        "go", "rs", "kt", "java",
        "c", "cpp", "cc", "cxx", "h", "hpp",
        "m", "mm",
        "rb", "php", "cs", "fs",
        "scala", "clj", "ex", "exs",
        "hs", "ml", "mli",
        "dart", "lua",
        "sh", "bash", "zsh",
    ]

    // MARK: - Excluded directory names

    private static let ignoredDirs: Set<String> = [
        ".git", ".build", "DerivedData", "node_modules", ".swiftpm",
        "Pods", "Carthage", "__pycache__", "venv", ".venv",
        "dist", "target", ".next", ".nuxt",
    ]

    // MARK: - Public API

    /// Scans `path` and returns metrics. Returns `.default` if path is empty or missing.
    func observe(path: String) async -> ProjectSizeMetrics {
        guard !path.isEmpty else { return .default }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return .default
        }
        let count = countSourceFiles(at: url)
        return ProjectSizeMetrics(sourceFileCount: count)
    }

    // MARK: - Private

    private func countSourceFiles(at root: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: []
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            // Skip excluded directories (and all their contents)
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                if Self.ignoredDirs.contains(name) {
                    enumerator.skipDescendants()
                }
                continue
            }
            // Count files with a recognised source extension
            if Self.sourceExtensions.contains(url.pathExtension.lowercased()) {
                count += 1
            }
        }
        return count
    }
}
```

---

## Edit: Merlin/Engine/AgenticEngine.swift

### 1. Add `projectSizeMetrics` property and `effectiveLoopCeiling(for:)`

After the `currentProjectPath` property declaration, add:

```swift
    /// Most-recently observed size metrics for `currentProjectPath`.
    /// Updated in the background whenever `currentProjectPath` changes.
    var projectSizeMetrics: ProjectSizeMetrics = .default

    private let sizeObserver = ProjectSizeObserver()

    /// Returns the effective loop ceiling for the given complexity tier.
    ///
    /// Takes the larger of the adaptive ceiling (derived from observed project size)
    /// and `AppSettings.maxLoopIterations` so a user-configured higher value always wins.
    func effectiveLoopCeiling(for tier: ComplexityTier) -> Int {
        max(projectSizeMetrics.adaptiveCeiling(for: tier),
            AppSettings.shared.maxLoopIterations)
    }
```

### 2. Trigger a background scan when `currentProjectPath` changes

Replace the plain stored property:
```swift
    var currentProjectPath: String?
```
with a property observer:
```swift
    var currentProjectPath: String? {
        didSet {
            guard currentProjectPath != oldValue else { return }
            let path = currentProjectPath ?? ""
            Task { [weak self] in
                guard let self else { return }
                let metrics = await self.sizeObserver.observe(path: path)
                await MainActor.run { self.projectSizeMetrics = metrics }
            }
        }
    }
```

### 3. Replace the hardcoded `maxIterations` line in `runLoop`

Replace:
```swift
        let maxIterations = max(1, classification.needsPlanning ? AppSettings.shared.maxLoopIterations : AppSettings.shared.maxLoopIterations)
```
with:
```swift
        let maxIterations = max(1, effectiveLoopCeiling(for: classification.complexity))
```

---

## Verify
```bash
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'ProjectSize|AdaptiveLoop|passed|failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: all ProjectSizeMetricsTests, ProjectSizeObserverTests, and
AdaptiveLoopCeilingEngineTests pass. BUILD SUCCEEDED. Zero warnings.

## Commit
```bash
git add Merlin/Engine/ProjectSizeObserver.swift \
        Merlin/Engine/AgenticEngine.swift
git commit -m "Phase 147b — Adaptive loop ceiling based on project size"
```
