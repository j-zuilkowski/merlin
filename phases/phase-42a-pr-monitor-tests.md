# Phase 42a — PRMonitor Tests

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 41b complete: SchedulerEngine + ScheduledTask + SchedulerView.

New surface introduced in phase 42b:
  - `PRStatus` — struct: number (Int), title, headSHA, checksState (ChecksState), url
  - `ChecksState` enum: pending, passed, failed, unknown
  - `PRMonitor` — @MainActor ObservableObject: `start(projectPath:token:)` begins polling;
    `stop()` cancels; interval: 60s active / 300s background (NSWorkspace notification);
    on checksFailed → posts UNUserNotification; on checksPassed && autoMergeEnabled → merges;
    `autoMergeEnabled: Bool`; `monitoredPRs: [PRStatus]`
  - `PRMonitor.detectRepoInfo(projectPath:) -> RepoInfo?` — parses `git remote -v` to extract
    owner/repo for GitHub

TDD coverage:
  File 1 — PRMonitorTests: detectRepoInfo parses HTTPS and SSH remote URLs;
            PRStatus JSON decoding; ChecksState transitions

---

## Write to: MerlinTests/Unit/PRMonitorTests.swift

```swift
import XCTest
@testable import Merlin

final class PRMonitorTests: XCTestCase {

    // MARK: - RepoInfo detection

    func testDetectRepoInfoFromHTTPSRemote() {
        let remoteOutput = "origin\thttps://github.com/jzuilko/merlin.git (fetch)"
        let info = PRMonitor.parseRepoInfo(from: remoteOutput)
        XCTAssertEqual(info?.owner, "jzuilko")
        XCTAssertEqual(info?.repo, "merlin")
    }

    func testDetectRepoInfoFromSSHRemote() {
        let remoteOutput = "origin\tgit@github.com:jzuilko/merlin.git (fetch)"
        let info = PRMonitor.parseRepoInfo(from: remoteOutput)
        XCTAssertEqual(info?.owner, "jzuilko")
        XCTAssertEqual(info?.repo, "merlin")
    }

    func testDetectRepoInfoFromHTTPSWithoutDotGit() {
        let remoteOutput = "origin\thttps://github.com/org/my-repo (fetch)"
        let info = PRMonitor.parseRepoInfo(from: remoteOutput)
        XCTAssertEqual(info?.owner, "org")
        XCTAssertEqual(info?.repo, "my-repo")
    }

    func testDetectRepoInfoReturnsNilForNonGitHub() {
        let remoteOutput = "origin\thttps://gitlab.com/org/repo.git (fetch)"
        let info = PRMonitor.parseRepoInfo(from: remoteOutput)
        XCTAssertNil(info, "Non-GitHub remotes must return nil")
    }

    func testDetectRepoInfoReturnsNilForEmptyOutput() {
        let info = PRMonitor.parseRepoInfo(from: "")
        XCTAssertNil(info)
    }

    // MARK: - ChecksState

    func testChecksStateDecodesSuccessAsPassed() throws {
        let json = #"{"state": "success"}"#
        let status = try JSONDecoder().decode(ChecksStateWrapper.self, from: Data(json.utf8))
        XCTAssertEqual(status.state, .passed)
    }

    func testChecksStateDecodesFailureAsFailed() throws {
        let json = #"{"state": "failure"}"#
        let status = try JSONDecoder().decode(ChecksStateWrapper.self, from: Data(json.utf8))
        XCTAssertEqual(status.state, .failed)
    }

    func testChecksStateDecodesUnknownState() throws {
        let json = #"{"state": "something_new"}"#
        let status = try JSONDecoder().decode(ChecksStateWrapper.self, from: Data(json.utf8))
        XCTAssertEqual(status.state, .unknown)
    }

    // MARK: - PRStatus JSON decoding

    func testPRStatusDecodesFromGitHubAPIShape() throws {
        let json = """
        {
          "number": 42,
          "title": "Add dark mode",
          "head": { "sha": "abc123" },
          "html_url": "https://github.com/owner/repo/pull/42"
        }
        """
        let pr = try JSONDecoder().decode(PRStatus.self, from: Data(json.utf8))
        XCTAssertEqual(pr.number, 42)
        XCTAssertEqual(pr.title, "Add dark mode")
        XCTAssertEqual(pr.headSHA, "abc123")
        XCTAssertEqual(pr.url, "https://github.com/owner/repo/pull/42")
    }
}

// Minimal wrapper for ChecksState decoding test
private struct ChecksStateWrapper: Decodable {
    let state: ChecksState
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|BUILD SUCCEEDED|BUILD FAILED' | head -20
```

Expected: `BUILD FAILED` with errors referencing `PRMonitor`, `PRStatus`, `ChecksState`,
`RepoInfo`, `ChecksStateWrapper`.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/PRMonitorTests.swift
git commit -m "Phase 42a — PRMonitorTests (failing)"
```
