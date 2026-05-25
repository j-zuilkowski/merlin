# Task 278a — v2.2.2 Release Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 277 complete: telemetry test-seam cleanup landed; full suite green headless.
`origin/main` pushed to `152654d`.

v2.2.2 is a **patch release**. It ships the task 274–277 work — the CI-readiness
remediation, two engine regression fixes (the ~199-retry escalation loop and the
`ComplexityTier` step-drop crash), and the telemetry test-seam cleanup — as a numbered
version. The `v2.2.1` tag stays at `0e34986` as an unreleased intermediate; v2.2.2 is
tagged at the current HEAD so the release contains those fixes.

New surface introduced in task 278b:
  - `project.yml`: `MARKETING_VERSION "2.2.2"`, `CURRENT_PROJECT_VERSION 19`.
  - `RELEASE-v2.2.2.md` at the repository root.

TDD coverage:
  File 1 — `MerlinTests/Unit/AppVersion222Tests.swift`: the bundle short version is
    `2.2.2` and the build number is `19`. Mirrors `AppVersion221Tests.swift`.
  File 2 — `MerlinTests/Unit/ReleaseNotes222Tests.swift`: `RELEASE-v2.2.2.md` exists at
    the repo root with the four required section headers. Mirrors `ReleaseNotes221Tests.swift`.

---

## Write to: MerlinTests/Unit/AppVersion222Tests.swift

```swift
import XCTest
@testable import Merlin

final class AppVersion222Tests: XCTestCase {

    func testMarketingVersionIs222() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "2.2.2",
                       "MARKETING_VERSION must be 2.2.2 for the v2.2.2 release")
    }

    func testBuildNumberIs19() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertEqual(build, "19",
                       "CURRENT_PROJECT_VERSION must be 19 for the v2.2.2 release")
    }
}
```

## Write to: MerlinTests/Unit/ReleaseNotes222Tests.swift

```swift
import XCTest
@testable import Merlin

final class ReleaseNotes222Tests: XCTestCase {

    /// Walks up from this test file to the repository root.
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // MerlinTests
            .deletingLastPathComponent()   // repo root
    }

    func testReleaseNotesFileExists() {
        let notes = repoRoot().appendingPathComponent("RELEASE-v2.2.2.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: notes.path),
                      "RELEASE-v2.2.2.md must exist at the repository root")
    }

    func testReleaseNotesHasRequiredSections() throws {
        let notes = repoRoot().appendingPathComponent("RELEASE-v2.2.2.md")
        let text = try String(contentsOf: notes, encoding: .utf8)

        for header in ["## Summary", "## What's new",
                       "## Internal changes", "## Migration"] {
            XCTAssertTrue(text.contains(header),
                          "RELEASE-v2.2.2.md must contain the '\(header)' section")
        }
    }
}
```

---

## Regenerate the Xcode project

The two new test files must be registered in the `MerlinTests` target. `project.yml`
uses a directory-glob source (`sources: [MerlinTests/, …]`), so a newly added `.swift`
file is **not** in `project.pbxproj` until the project is regenerated. Skip this and the
files compile-silent and never run.

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
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

Expected: **BUILD SUCCEEDED**, but `AppVersion222Tests` and `ReleaseNotes222Tests`
**FAIL at runtime** — the version is still 2.2.1/18 and `RELEASE-v2.2.2.md` does not
exist yet. Every other test still passes (gated engine tests skip headless). 278b makes
the new tests pass.

**Sanity check:** the names `AppVersion222Tests` and `ReleaseNotes222Tests` MUST appear
in the test log. If they do not appear at all (a `TEST SUCCEEDED` with neither name
present), the project was not regenerated — the test files are not in the `MerlinTests`
target. Run `xcodegen generate` and re-verify before committing.

## Commit

```bash
git add tasks/task-278a-v2-2-2-release-tests.md \
    MerlinTests/Unit/AppVersion222Tests.swift \
    MerlinTests/Unit/ReleaseNotes222Tests.swift \
    Merlin.xcodeproj/project.pbxproj
git commit -m "Task 278a — V2_2_2ReleaseTests (failing)"
```
