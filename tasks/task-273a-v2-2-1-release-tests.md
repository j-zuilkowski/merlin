# Task 273a — v2.2.1 Release Tests

## Traceability

- Vision reference: vision.md#active
- Spec reference: spec.md#overview

## Behavior

WHEN this task is executed THE system SHALL deliver the behavior, verification, or documentation outcome described by this task file.

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Task 272b complete: the v2.2 discipline subsystem is wired into the running app.

This is the release task for **v2.2.1 — Project Discipline remediation**. It ships the
correctness fixes from  tasks 266–272. Task 273a writes failing tests that assert the
v2.2.1 version numbers and the release-notes file; task 273b bumps the version, writes
the notes, regenerates the project, and tags.

New surface introduced in task 273b:
  - `project.yml`: `MARKETING_VERSION` 2.2.0 → 2.2.1, `CURRENT_PROJECT_VERSION` 17 → 18.
  - `RELEASE-v2.2.1.md` — new file at repo root.

TDD coverage:
  File 1 — `AppVersion221Tests.swift`: `Bundle.main` short version string is `"2.2.1"`
    and the bundle version is `"18"`.
  File 2 — `ReleaseNotes221Tests.swift`: `RELEASE-v2.2.1.md` exists at the repo root and
    contains the four required section headers.

---

## Write to: MerlinTests/Unit/AppVersion221Tests.swift

```swift
import XCTest
@testable import Merlin

final class AppVersion221Tests: XCTestCase {

    func testMarketingVersionIs221() {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertEqual(short, "2.2.1",
            "MARKETING_VERSION must be 2.2.1 for the v2.2.1 release")
    }

    func testBuildNumberIs18() {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        XCTAssertEqual(build, "18",
            "CURRENT_PROJECT_VERSION must be 18 for the v2.2.1 release")
    }
}
```

---

## Write to: MerlinTests/Unit/ReleaseNotes221Tests.swift

```swift
import XCTest
@testable import Merlin

final class ReleaseNotes221Tests: XCTestCase {

    /// Walks up from this test file to the repository root.
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Unit
            .deletingLastPathComponent()   // MerlinTests
            .deletingLastPathComponent()   // repo root
    }

    func testReleaseNotesFileExists() {
        let notes = repoRoot().appendingPathComponent("RELEASE-v2.2.1.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: notes.path),
            "RELEASE-v2.2.1.md must exist at the repository root")
    }

    func testReleaseNotesHasRequiredSections() throws {
        let notes = repoRoot().appendingPathComponent("RELEASE-v2.2.1.md")
        let text = try String(contentsOf: notes, encoding: .utf8)

        for header in ["## Summary", "## What's new",
                       "## Internal changes", "## Migration"] {
            XCTAssertTrue(text.contains(header),
                "RELEASE-v2.2.1.md must contain the '\(header)' section")
        }
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

xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived \
    CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: **BUILD SUCCEEDED**, but both new test classes FAIL at runtime — the bundle
still reports 2.2.0 / build 17 and `RELEASE-v2.2.1.md` does not exist. Task 273b makes
them pass.

## Commit

```bash
git add tasks/task-273a-v2-2-1-release-tests.md \
    MerlinTests/Unit/AppVersion221Tests.swift \
    MerlinTests/Unit/ReleaseNotes221Tests.swift
git commit -m "Task 273a — AppVersion221Tests + ReleaseNotes221Tests (failing)"
```
