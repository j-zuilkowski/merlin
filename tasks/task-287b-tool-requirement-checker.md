# Task 287b — Tool Requirement Checker

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 287a complete: failing tests for `ToolRequirement` / `ToolRequirements` /
`ToolRequirementChecker`.

After this task, when an in-app feature is about to shell out to an external CLI tool
that is not installed, Merlin detects it on first use and surfaces a prompt instead of
letting a raw "command not found" escape. For the Homebrew-safe subset it offers a
one-click install (`brew install <formula>`, run only on explicit confirmation); for
everything else it shows the requirement and the install command/URL but never runs the
installer itself.

---

## Edit

### 1. New file — `Merlin/Tools/ToolRequirement.swift`

```swift
import Foundation

/// One external command-line tool Merlin shells out to (see Requirements.md §10).
struct ToolRequirement: Sendable, Identifiable, Equatable {
    let id: String            // stable key, e.g. "xcodegen"
    let displayName: String   // human label, e.g. "XcodeGen"
    let executable: String    // name looked up on PATH
    let purpose: String       // why Merlin needs it — shown in the prompt
    let install: InstallMethod

    enum InstallMethod: Sendable, Equatable {
        /// Brew-safe: Merlin can install it with one confirmed `brew install <formula>`.
        case homebrew(formula: String)
        /// Not auto-installable. `command` (if any) and `url` are shown to the user;
        /// Merlin never runs them itself — covers curl-pipe-sh installers, pip, and
        /// .dmg/cask apps.
        case manual(command: String?, url: String)
    }

    /// True only for `.homebrew` — the one-click-installable subset.
    var isAutoInstallable: Bool {
        if case .homebrew = install { return true }
        return false
    }
}

/// The known external tools, mirrored from Requirements.md §10 / §5 / §7.
/// NOTE: named `ToolRequirements`, not `ToolRegistry` — `ToolRegistry.shared` is the
/// runtime built-in tool registry and must not be shadowed.
enum ToolRequirements {

    static let all: [ToolRequirement] = [
        // ── Homebrew-safe — Merlin can install these itself ──────────────────
        ToolRequirement(id: "xcodegen", displayName: "XcodeGen", executable: "xcodegen",
            purpose: "Regenerate the Xcode project after project.yml changes.",
            install: .homebrew(formula: "xcodegen")),
        ToolRequirement(id: "gh", displayName: "GitHub CLI", executable: "gh",
            purpose: "Create GitHub releases.",
            install: .homebrew(formula: "gh")),
        ToolRequirement(id: "vale", displayName: "Vale", executable: "vale",
            purpose: "Prose readability grading for Project Discipline docs.",
            install: .homebrew(formula: "vale")),
        ToolRequirement(id: "ngspice", displayName: "ngspice", executable: "ngspice",
            purpose: "SPICE circuit simulation for the electronics domain.",
            install: .homebrew(formula: "ngspice")),
        ToolRequirement(id: "git", displayName: "Git", executable: "git",
            purpose: "Worktree isolation, commits, and tags.",
            install: .homebrew(formula: "git")),
        // ── Manual — detect and link only, never auto-installed ──────────────
        ToolRequirement(id: "cargo", displayName: "Rust toolchain (cargo)",
            executable: "cargo",
            purpose: "Build and test Rust projects.",
            install: .manual(
                command: "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh",
                url: "https://www.rust-lang.org/tools/install")),
        ToolRequirement(id: "python", displayName: "Python 3",
            executable: "python3",
            purpose: "LoRA self-training (mlx_lm).",
            install: .manual(command: nil,
                             url: "https://www.python.org/downloads/macos/")),
        ToolRequirement(id: "lms", displayName: "LM Studio CLI", executable: "lms",
            purpose: "LM Studio model-management fallback.",
            install: .manual(command: nil, url: "https://lmstudio.ai/")),
        ToolRequirement(id: "kicad-cli", displayName: "KiCad", executable: "kicad-cli",
            purpose: "PCB and schematic workflows (electronics domain).",
            install: .manual(command: "brew install --cask kicad",
                             url: "https://www.kicad.org/")),
    ]

    static func named(_ id: String) -> ToolRequirement? {
        all.first { $0.id == id }
    }
}
```

`xcodebuild` is deliberately **not** in the registry — it ships with Xcode, cannot be
installed standalone, and its absence means Xcode itself is missing (a different,
larger problem the registry should not pretend to fix).

### 2. New file — `Merlin/Tools/ToolRequirementChecker.swift`

```swift
import Foundation

/// Detects whether an external CLI tool is installed and installs the brew-safe
/// ones on request. The detector is injectable so tests never touch the real PATH
/// or Homebrew.
actor ToolRequirementChecker {

    static let shared = ToolRequirementChecker()

    /// Returns true when `executable` resolves to an installed binary.
    typealias Detector = @Sendable (_ executable: String) async -> Bool

    enum ToolRequirementError: Error, Sendable {
        case notAutoInstallable(String)
        case installFailed(String)
        case homebrewMissing
    }

    private let detector: Detector
    private var availabilityCache: [String: Bool] = [:]

    init(detector: @escaping Detector = ToolRequirementChecker.pathDetector) {
        self.detector = detector
    }

    /// True when the tool is installed. Cached after the first lookup.
    func isAvailable(_ requirement: ToolRequirement) async -> Bool {
        if let cached = availabilityCache[requirement.id] { return cached }
        let present = await detector(requirement.executable)
        availabilityCache[requirement.id] = present
        return present
    }

    /// The requirement for `id`, but only when it is missing. nil means it is
    /// installed, or `id` is not a known requirement.
    func missingRequirement(id: String) async -> ToolRequirement? {
        guard let req = ToolRequirements.named(id) else { return nil }
        return await isAvailable(req) ? nil : req
    }

    /// Installs a brew-safe requirement with one `brew install <formula>`.
    /// Throws `.notAutoInstallable` for a `.manual` tool — Merlin never runs those
    /// installers. Emits `tool.requirement.installed` / `tool.requirement.install_failed`
    /// telemetry. On success the availability cache entry is cleared so the next
    /// `isAvailable` re-detects.
    func installViaHomebrew(_ requirement: ToolRequirement) async throws {
        guard case .homebrew(let formula) = requirement.install else {
            throw ToolRequirementError.notAutoInstallable(requirement.id)
        }
        guard let brew = Self.locateHomebrew() else {
            throw ToolRequirementError.homebrewMissing
        }
        // Run `<brew> install <formula>` via Process; capture exit status.
        // Non-zero exit → throw .installFailed(formula). On success:
        availabilityCache[requirement.id] = nil
        // emit tool.requirement.installed telemetry
    }

    // MARK: - Production detection

    /// Looks an executable up the way a Finder-launched app must: a GUI process
    /// inherits a stripped PATH, so `which` alone misses Homebrew/cargo binaries.
    /// Check `which` first, then a fixed set of common install directories.
    static let pathDetector: Detector = { executable in
        // 1. `/usr/bin/which <executable>` — exit 0 ⇒ present.
        // 2. Fallback: probe these dirs for an executable file named `executable`:
        //      /opt/homebrew/bin, /usr/local/bin, /usr/bin, /bin,
        //      ~/.cargo/bin, ~/.lmstudio/bin, /Applications/KiCad/...
        // Return true on the first hit.
        ...
    }

    private static func locateHomebrew() -> String? {
        for path in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }
}
```

### 3. New file — `Merlin/Tools/ToolRequirementCoordinator.swift` (first-use gate + UI)

```swift
import SwiftUI

/// Surfaces a missing-tool prompt. A feature calls `ensure(_:)` before its first use
/// of an external tool; on a miss the coordinator raises `pending`, which the app
/// presents as a sheet.
@MainActor
final class ToolRequirementCoordinator: ObservableObject {
    static let shared = ToolRequirementCoordinator()

    @Published var pending: ToolRequirement?
    @Published var isInstalling = false

    /// Returns true when the tool is present (caller proceeds). On a miss it raises
    /// `pending` and returns false — the caller should abort the current action; the
    /// user retries after resolving the prompt.
    func ensure(_ id: String) async -> Bool {
        guard let missing = await ToolRequirementChecker.shared.missingRequirement(id: id)
        else { return true }
        pending = missing
        return false
    }

    /// Invoked by the sheet's "Install" button — only enabled for `.homebrew` tools.
    func installPending() async { ... }   // sets isInstalling, calls installViaHomebrew,
                                          // clears `pending` on success
}
```

`ToolRequirementSheet` — a small SwiftUI view bound via `.sheet(item: $coordinator.pending)`
at the app root. It shows `displayName`, `purpose`, and:
  - `.homebrew` → an **Install with Homebrew** button (runs `installPending()`), plus a
    "Cancel" button.
  - `.manual` → the install `url` as a link and the `command` (if any) in a copyable
    field, plus a "Done" button. No install button — Merlin does not run these.

Present the sheet once, at the top-level `WindowGroup`/root view, observing
`ToolRequirementCoordinator.shared`.

### 4. Wire the gate at first-use sites

Before the in-app code spawns one of these tools, call the gate and abort cleanly on a
miss. Match on the subprocess invocation, not a line number:

| Tool id | Gate before… |
|---|---|
| `xcodegen` | the `xcodegen` invocation in `XcodeTools` (project regeneration) |
| `cargo` | the `cargo` invocation in the Rust `ProjectAdapter` build/test path |
| `vale` | the `vale` invocation in `ProseReadabilityChecker` / `ProseGate` |

Pattern at each site:

```swift
guard await ToolRequirementCoordinator.shared.ensure("xcodegen") else {
    // tool missing — prompt raised; abort this action, surface a clear status.
    return .toolUnavailable("xcodegen")
}
```

The gate is reusable — other subprocess sites (`gh`, `python`, `lms`, KiCad) can adopt
the same one-line `ensure(_:)` call in later  tasks; this task wires the three above
as the high-traffic cases.

---

## Verify

```bash
xcodegen generate

xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**, all task 287a tests pass, no prior task regresses.

**Manual check:** temporarily rename your `xcodegen` binary, trigger a project
regeneration in-app — the missing-tool sheet must appear with an **Install with
Homebrew** button. Restore the binary afterwards.

## Commit

```bash
git add tasks/task-287b-tool-requirement-checker.md \
    Merlin/Tools/ToolRequirement.swift \
    Merlin/Tools/ToolRequirementChecker.swift \
    Merlin/Tools/ToolRequirementCoordinator.swift \
    Merlin.xcodeproj/project.pbxproj \
    <the XcodeTools / Rust adapter / ProseReadabilityChecker files wired in step 4> \
    <the root view file where the sheet is presented>
git commit -m "Task 287b — Tool requirement checker: detect on first use, offer brew install"
```

(Run `xcodegen generate` for the three new files; commit the regenerated
`project.pbxproj`.)

## Fixes

`Requirements.md` §10's external CLI tools are now detected in-app on first use. A
missing brew-safe tool (`xcodegen`, `gh`, `vale`, `ngspice`, `git`) can be installed
with one confirmed `brew install`; a missing non-brew tool (`cargo`, `python`, `lms`,
KiCad) surfaces its install command/URL without Merlin running the installer. A raw
"command not found" from a feature subprocess is replaced by an actionable prompt.

## Follow-up (not in this task)

The gate is wired at three high-traffic sites. Extending `ensure(_:)` to the remaining
subprocess sites (`gh` release path, `python`/mlx_lm LoRA path, `lms`, KiCad domain
tools) is a mechanical follow-up — one `ensure(_:)` call each — separate from this
task's core registry + checker.
