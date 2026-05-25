# Phase 261a — project:revise Skill Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 260b complete: project:phase SKILL.md installed.

New surface introduced in phase 261b:
  - `~/.merlin/skills/project-revise/SKILL.md` — the `project:revise` skill file.

TDD coverage:
  File 1 — `MerlinTests/Unit/ProjectReviseSkillTests.swift`:
    Skill file exists; has "## Trigger", "## Steps", "## Output"; mentions
    "DisciplineEngine" or "scan"; mentions dismiss/defer workflow.

---

## Write to

- `MerlinTests/Unit/ProjectReviseSkillTests.swift`

### MerlinTests/Unit/ProjectReviseSkillTests.swift

```swift
import XCTest

final class ProjectReviseSkillTests: XCTestCase {

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-revise/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-revise/SKILL.md not found. Run phase 261b.")
    }

    func testSkillHasRequiredSections() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"))
        XCTAssertTrue(text.contains("## Steps"))
        XCTAssertTrue(text.contains("## Output"))
    }

    func testSkillMentionsScan() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("scan") ||
                      text.contains("DisciplineEngine"),
                      "project:revise should mention scanning for drift")
    }

    func testSkillMentionsDismiss() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("dismiss") ||
                      text.lowercased().contains("defer"),
                      "project:revise should mention dismiss/defer workflow")
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

Expected: **BUILD SUCCEEDED** but tests **FAIL** at runtime (skill file absent).

## Commit

```bash
git add tasks/task-261a-project-revise-skill-tests.md \
    MerlinTests/Unit/ProjectReviseSkillTests.swift
git commit -m "Phase 261a — ProjectReviseSkillTests (failing)"
```
