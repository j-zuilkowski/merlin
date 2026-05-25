# Task 263a — project:adopt Skill Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 262b complete: project:release SKILL.md installed.

New surface introduced in task 263b:
  - `~/.merlin/skills/project-adopt/SKILL.md` — the `project:adopt` skill file.
  - First adoption target is Merlin itself (the skill references this).

TDD coverage:
  File 1 — `MerlinTests/Unit/ProjectAdoptSkillTests.swift`:
    Skill file exists; has required sections; mentions "baseline"; mentions "adopt";
    mentions "existing project"; mentions manual_coverage_baseline.

---

## Write to

- `MerlinTests/Unit/ProjectAdoptSkillTests.swift`

### MerlinTests/Unit/ProjectAdoptSkillTests.swift

```swift
import XCTest

final class ProjectAdoptSkillTests: XCTestCase {

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-adopt/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-adopt/SKILL.md not found. Run task 263b.")
    }

    func testSkillHasRequiredSections() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"))
        XCTAssertTrue(text.contains("## Steps"))
        XCTAssertTrue(text.contains("## Output"))
    }

    func testSkillMentionsBaseline() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("baseline"),
                      "project:adopt should mention baseline")
    }

    func testSkillMentionsManualCoverageBaseline() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("manual_coverage_baseline") ||
                      text.lowercased().contains("coverage baseline"),
                      "project:adopt should mention manual coverage baseline")
    }

    func testSkillMentionsExistingProject() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("existing project") ||
                      text.lowercased().contains("existing codebase"),
                      "project:adopt should target existing projects")
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

Expected: **BUILD SUCCEEDED** but tests **FAIL** at runtime.

## Commit

```bash
git add tasks/task-263a-project-adopt-skill-tests.md \
    MerlinTests/Unit/ProjectAdoptSkillTests.swift
git commit -m "Task 263a — ProjectAdoptSkillTests (failing)"
```
