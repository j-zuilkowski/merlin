# Phase 260a — project:phase Skill Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 259b complete: project:init SKILL.md installed.

New surface introduced in phase 260b:
  - `~/.merlin/skills/project-phase/SKILL.md` — the `project:phase` skill file.

TDD coverage:
  File 1 — `MerlinTests/Unit/ProjectPhaseSkillTests.swift`:
    `~/.merlin/skills/project-phase/SKILL.md` exists; contains "## Trigger";
    contains "## Steps"; contains "## Output"; mentions "NNa" and "NNb".

---

## Write to

- `MerlinTests/Unit/ProjectPhaseSkillTests.swift`

### MerlinTests/Unit/ProjectPhaseSkillTests.swift

```swift
import XCTest

final class ProjectPhaseSkillTests: XCTestCase {

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-phase/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-phase/SKILL.md not found. Run phase 260b.")
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
        XCTAssertTrue(text.contains("NNa") || text.contains("phase-NNa"),
                      "SKILL.md should reference NNa phase files")
        XCTAssertTrue(text.contains("NNb") || text.contains("phase-NNb"),
                      "SKILL.md should reference NNb phase files")
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
git add phases/phase-260a-project-phase-skill-tests.md \
    MerlinTests/Unit/ProjectPhaseSkillTests.swift
git commit -m "Phase 260a — ProjectPhaseSkillTests (failing)"
```
