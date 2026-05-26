# Task 288a — Vision Launchpad Tests (failing)

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 287 complete: external CLI tools are detected on first use.

**The gap.** The Project Discipline subsystem's documented pipeline starts at
`spec.md` — there is no artifact upstream of it, so a raw idea has nowhere to
live before it is already hardened into a design decision. The chain should be:

```
vision.md  →  spec.md  →  tasks/  →  code
 (intent)      (committed design)  (specs)     (implementation)
```

`vision.md` becomes the launchpad: every new idea is captured there first, then promoted
to `spec.md`. It is a single document with two sections:
  - **## Active** — ideas captured, awaiting promotion to `spec.md`.
  - **## Deferred** — ideas consciously parked, each with a "reconsider when".

`spec.md` remains the source of truth for *what is being built*; `vision.md` is
the source of truth for *intent*, upstream of it.

Capture mechanism (per the chosen design): `project:init` **seeds `vision.md` with the
initial project idea** at scaffold time; later edits go through `project:revise`. No new
skill is added.

This task asserts (failing) that the `project:init` skill scaffolds and seeds
`vision.md`. Task 288b updates the skill files and docs. No Swift production code — the
"tests" are content assertions on the skill file, mirroring task 259a.

New surface introduced in task 288b:
  - `project:init` SKILL.md gains: an initial-idea capture step, a `vision.md` scaffold
    step (with `## Active` seeded / `## Deferred` empty), `vision.md` in both doc-set
    tiers, and the vision→architecture→task→code pipeline documented.
  - `project:adopt` SKILL.md gains: a step that incorporates an existing `vision.md` if
    the adopted project already has one, or creates the launchpad scaffold if not.
  - `project:revise` SKILL.md notes `vision.md` as a revisable doc (idea promotion).
  - This repo's own `vision.md` is restructured into `## Active` + `## Deferred`.

TDD coverage:
  File 1 — `MerlinTests/Unit/ProjectVisionLaunchpadTests.swift`: the installed
    `project:init` SKILL.md references `vision.md`, has an initial-idea capture/seed
    step, and documents the vision→architecture→task→code pipeline; the installed
    `project:adopt` SKILL.md incorporates an existing `vision.md`.

---

## Write to: MerlinTests/Unit/ProjectVisionLaunchpadTests.swift

```swift
import XCTest

/// Tests that the project:init skill scaffolds vision.md as the idea launchpad.
/// These tests build clean but FAIL at runtime until task 288b updates the skill.
final class ProjectVisionLaunchpadTests: XCTestCase {

    private let skillPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".merlin/skills/project-init/SKILL.md").path
    }()

    private let adoptSkillPath: String = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".merlin/skills/project-adopt/SKILL.md").path
    }()

    private func skillBody() throws -> String {
        try String(contentsOfFile: skillPath, encoding: .utf8)
    }

    private func adoptSkillBody() throws -> String {
        try String(contentsOfFile: adoptSkillPath, encoding: .utf8)
    }

    func testProjectInitSkillExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "project-init SKILL.md not found — task 259b must have run first.")
    }

    func testProjectInitScaffoldsVisionDoc() throws {
        let body = try skillBody()
        XCTAssertTrue(body.contains("vision.md"),
                      "project:init must scaffold vision.md as part of the doc set.")
    }

    func testProjectInitSeedsTheInitialIdea() throws {
        // The launchpad is seeded at scaffold time — init captures the project idea
        // and writes it into vision.md's Active section.
        let body = try skillBody().lowercased()
        XCTAssertTrue(body.contains("## active") || body.contains("active section"),
                      "vision.md scaffold must seed an Active section.")
        XCTAssertTrue(body.contains("deferred"),
                      "vision.md scaffold must include a Deferred section.")
    }

    func testProjectInitDocumentsThePipeline() throws {
        // The vision → spec → task → code pipeline must be stated in the skill
        // so the discipline workflow is explicit.
        let body = try skillBody().lowercased()
        let mentionsPipeline =
            body.contains("vision") && body.contains("spec")
            && body.contains("task") && body.contains("code")
        XCTAssertTrue(mentionsPipeline,
                      "project:init must document the vision→spec→task→code pipeline.")
    }

    func testProjectAdoptIncorporatesExistingVisionDoc() throws {
        // Adopting an existing project must recognise an existing vision.md rather than
        // ignore or clobber it, and give a vision-less project the launchpad scaffold.
        XCTAssertTrue(FileManager.default.fileExists(atPath: adoptSkillPath),
                      "project-adopt SKILL.md not found — task 263b must have run first.")
        let body = try adoptSkillBody()
        XCTAssertTrue(body.contains("vision.md"),
                      "project:adopt must incorporate an existing vision.md.")
    }
}
```

---

## Verify

```bash
xcodegen generate

xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** (no missing symbols — the tests are file-content
assertions), but `testProjectInitScaffoldsVisionDoc`, `testProjectInitSeedsTheInitialIdea`,
`testProjectInitDocumentsThePipeline`, and `testProjectAdoptIncorporatesExistingVisionDoc`
**FAIL at runtime** until task 288b updates the skill files.

## Commit

```bash
git add tasks/task-288a-vision-launchpad-tests.md \
    MerlinTests/Unit/ProjectVisionLaunchpadTests.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Task 288a — ProjectVisionLaunchpadTests (failing)"
```

(Run `xcodegen generate` so the new test file registers.)
