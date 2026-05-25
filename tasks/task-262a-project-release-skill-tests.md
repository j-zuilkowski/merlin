# Phase 262a — project:release Skill Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 261b complete: project:revise SKILL.md installed.

New surface introduced in phase 262b:
  - `~/.merlin/skills/project-release/SKILL.md` — the `project:release` skill file.

TDD coverage:
  File 1 — `MerlinTests/Unit/ProjectReleaseSkillTests.swift`:
    Skill file exists; has required sections; mentions "release gate"; mentions
    "RELEASE-v"; mentions "version bump"; mentions "gh release create".

---

## Write to

- `MerlinTests/Unit/ProjectReleaseSkillTests.swift`

### MerlinTests/Unit/ProjectReleaseSkillTests.swift

```swift
import XCTest

final class ProjectReleaseSkillTests: XCTestCase {

    private let skillPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/skills/project-release/SKILL.md").path
    }()

    func testSkillFileExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: skillPath),
                      "~/.merlin/skills/project-release/SKILL.md not found. Run phase 262b.")
    }

    func testSkillHasRequiredSections() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("## Trigger"))
        XCTAssertTrue(text.contains("## Steps"))
        XCTAssertTrue(text.contains("## Output"))
    }

    func testSkillMentionsReleaseGate() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("release gate"),
                      "project:release should mention 'release gate'")
    }

    func testSkillMentionsReleaseNotes() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("RELEASE-v"),
                      "project:release should mention RELEASE-vX.Y.Z.md")
    }

    func testSkillMentionsVersionBump() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.lowercased().contains("version bump") ||
                      text.lowercased().contains("bump version"),
                      "project:release should mention version bump")
    }

    func testSkillMentionsGhRelease() throws {
        let text = try String(contentsOfFile: skillPath, encoding: .utf8)
        XCTAssertTrue(text.contains("gh release create"),
                      "project:release should mention 'gh release create'")
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
git add tasks/task-262a-project-release-skill-tests.md \
    MerlinTests/Unit/ProjectReleaseSkillTests.swift
git commit -m "Phase 262a — ProjectReleaseSkillTests (failing)"
```
