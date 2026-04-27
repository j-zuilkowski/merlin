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

private struct ChecksStateWrapper: Decodable {
    let state: ChecksState
}
