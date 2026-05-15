# Phase 259a — project:init Skill Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 258b complete: OverrideAuditLog + weekly review event live.

Skills (phases 259–263) are SKILL.md files written to `~/.merlin/skills/project-*/SKILL.md`.
The `a` phase asserts the skill file does not yet exist (BUILD FAILED = skill file absent).
The `b` phase writes the SKILL.md content.

For phase 259a, the "test" is a Swift test that asserts the presence of
`~/.merlin/skills/project-init/SKILL.md` and verifies required section headings.
The skill file does not exist yet → BUILD SUCCEEDED but tests FAIL at runtime.

New surface introduced in phase 259b:
  - `~/.merlin/skills/project-init/SKILL.md` — the `project:init` skill file.

TDD coverage:
  File 1 — `MerlinTests/Unit/ProjectInitSkillTests.swift`:
    `~/.merlin/skills/project-init/SKILL.md` exists; contains "## Trigger";
    contains "## Steps"; contains "## Output".

---

## Write to

- `MerlinTests/Unit/ProjectInitSkillTests.swift`

### MerlinTests/Unit/ProjectInitSkillTests.swift

```swift
import XCTest

/// Tests that the project:init SKILL.md file is installed and well-formed.
/// These tests fail until phase 259b writes the skill file.
final class ProjectInitSkillTests: XCTestCase {

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-init/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-init/SKILL.md not found. Run phase 259b.")
    }

    func testSkillHasTriggerSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"),
                      "SKILL.md must contain '## Trigger'")
    }

    func testSkillHasStepsSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Steps"),
                      "SKILL.md must contain '## Steps'")
    }

    func testSkillHasOutputSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Output"),
                      "SKILL.md must contain '## Output'")
    }

    func testSkillMentionsAdapter() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("adapter"),
                      "project:init SKILL.md should reference 'adapter'")
    }
}
```

---

## Verify

```bash
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED** (the test file compiles), but tests will **FAIL** at runtime
because the skill file does not yet exist.

## Commit

```bash
git add phases/phase-259a-project-init-skill-tests.md \
    MerlinTests/Unit/ProjectInitSkillTests.swift
git commit -m "Phase 259a — ProjectInitSkillTests (failing)"
```
