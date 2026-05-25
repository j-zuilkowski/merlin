# Task 260a — project:task Skill Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 259b complete: project:init SKILL.md installed.

New surface introduced in task 260b:
  - `~/.merlin/skills/project-task/SKILL.md` — the `project:task` skill file.

TDD coverage:
  File 1 — `MerlinTests/Unit/ProjectTaskSkillTests.swift`:
    `~/.merlin/skills/project-task/SKILL.md` exists; contains "## Trigger";
    contains "## Steps"; contains "## Output"; mentions "NNa" and "NNb".

---

## Write to

- `MerlinTests/Unit/ProjectTaskSkillTests.swift`

### MerlinTests/Unit/ProjectTaskSkillTests.swift

```swift
import XCTest

final class ProjectTaskSkillTests: XCTestCase {

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-task/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-task/SKILL.md not found. Run task 260b.")
    }

    func testSkillHasTriggerSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"))
    }

    func testSkillHasStepsSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Steps"))
    }

    func testSkillHasOutputSection() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Output"))
    }

    func testSkillMentionsNNaAndNNb() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("NNa") || text.contains("task-NNa"),
                      "SKILL.md should reference NNa task files")
        XCTAssertTrue(text.contains("NNb") || text.contains("task-NNb"),
                      "SKILL.md should reference NNb task files")
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
git add tasks/task-260a-project-task-skill-tests.md \
    MerlinTests/Unit/ProjectTaskSkillTests.swift
git commit -m "Task 260a — ProjectTaskSkillTests (failing)"
```
