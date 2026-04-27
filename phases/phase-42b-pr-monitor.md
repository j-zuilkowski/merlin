# Phase 42b — PRMonitor Implementation

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 42a complete: failing PRMonitorTests in place.

---

## Write to: Merlin/Connectors/PRMonitor.swift

```swift
import Foundation
import UserNotifications
import Combine

struct RepoInfo: Sendable {
    var owner: String
    var repo: String
}

enum ChecksState: String, Decodable, Sendable, Equatable {
    case pending
    case passed   = "success"
    case failed   = "failure"
    case error    = "error"
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ChecksState(rawValue: raw) ?? .unknown
    }
}

struct PRStatus: Decodable, Identifiable, Sendable {
    var id: Int { number }
    var number: Int
    var title: String
    var headSHA: String
    var url: String
    var checksState: ChecksState = .unknown

    enum CodingKeys: String, CodingKey {
        case number, title, head
        case url = "html_url"
    }

    struct Head: Decodable {
        var sha: String
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        number  = try c.decode(Int.self, forKey: .number)
        title   = try c.decode(String.self, forKey: .title)
        url     = try c.decode(String.self, forKey: .url)
        headSHA = try c.decode(Head.self, forKey: .head).sha
    }
}

@MainActor
final class PRMonitor: ObservableObject {
    @Published private(set) var monitoredPRs: [PRStatus] = []
    @Published var autoMergeEnabled: Bool = false

    private var token: String = ""
    private var repoInfo: RepoInfo?
    private var pollTask: Task<Void, Never>?
    private var activeInterval: TimeInterval = 60
    private var backgroundInterval: TimeInterval = 300

    // MARK: - Public API

    func start(projectPath: String, token: String) {
        self.token = token
        self.repoInfo = Self.detectRepoInfo(projectPath: projectPath)
        guard repoInfo != nil else { return }
        startPolling()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Repo detection

    static func detectRepoInfo(projectPath: String) -> RepoInfo? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        proc.arguments = ["-C", projectPath, "remote", "-v"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return nil }
        proc.waitUntilExit()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(),
                            encoding: .utf8) ?? ""
        return parseRepoInfo(from: output)
    }

    static func parseRepoInfo(from remoteOutput: String) -> RepoInfo? {
        for line in remoteOutput.components(separatedBy: "\n") {
            // HTTPS: https://github.com/owner/repo.git
            if let match = line.range(of: #"https://github\.com/([^/]+)/([^.\s]+)(\.git)?"#,
                                      options: .regularExpression) {
                let s = String(line[match])
                let parts = s.replacingOccurrences(of: ".git", with: "")
                    .components(separatedBy: "github.com/").last?
                    .components(separatedBy: "/")
                if let owner = parts?.first, let repo = parts?.dropFirst().first {
                    return RepoInfo(owner: owner, repo: String(repo))
                }
            }
            // SSH: git@github.com:owner/repo.git
            if let match = line.range(of: #"git@github\.com:([^/]+)/([^.\s]+)(\.git)?"#,
                                      options: .regularExpression) {
                let s = String(line[match])
                let colon = s.components(separatedBy: ":").last ?? ""
                let parts = colon.replacingOccurrences(of: ".git", with: "")
                    .components(separatedBy: "/")
                if parts.count >= 2 {
                    return RepoInfo(owner: parts[0], repo: parts[1])
                }
            }
        }
        return nil
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.poll()
                let interval = self?.activeInterval ?? 60
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    private func poll() async {
        guard let info = repoInfo else { return }
        let prs = await fetchOpenPRs(info: info)
        var updated: [PRStatus] = []
        for var pr in prs {
            pr.checksState = await fetchChecksState(info: info, sha: pr.headSHA)
            updated.append(pr)
        }

        let prevStates = Dictionary(uniqueKeysWithValues: monitoredPRs.map { ($0.number, $0.checksState) })
        monitoredPRs = updated

        for pr in updated {
            let prev = prevStates[pr.number]
            if pr.checksState == .failed && prev != .failed {
                postFailureNotification(pr: pr)
            } else if pr.checksState == .passed && prev != .passed && autoMergeEnabled {
                await mergePR(info: info, number: pr.number)
            }
        }
    }

    // MARK: - GitHub API

    private func fetchOpenPRs(info: RepoInfo) async -> [PRStatus] {
        let urlStr = "https://api.github.com/repos/\(info.owner)/\(info.repo)/pulls?state=open&per_page=20"
        guard let url = URL(string: urlStr) else { return [] }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        return (try? JSONDecoder().decode([PRStatus].self, from: data)) ?? []
    }

    private func fetchChecksState(info: RepoInfo, sha: String) async -> ChecksState {
        let urlStr = "https://api.github.com/repos/\(info.owner)/\(info.repo)/commits/\(sha)/status"
        guard let url = URL(string: urlStr) else { return .unknown }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let json = try? JSONDecoder().decode([String: JSONValue].self, from: data),
              case .string(let state) = json["state"]
        else { return .unknown }
        return ChecksState(rawValue: state) ?? .unknown
    }

    private func mergePR(info: RepoInfo, number: Int) async {
        let urlStr = "https://api.github.com/repos/\(info.owner)/\(info.repo)/pulls/\(number)/merge"
        guard let url = URL(string: urlStr) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.httpBody = try? JSONEncoder().encode(["merge_method": "squash"])
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Notifications

    private func postFailureNotification(pr: PRStatus) {
        let content = UNMutableNotificationContent()
        content.title = "CI Failed — PR #\(pr.number)"
        content.body = pr.title
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "pr-fail-\(pr.number)", content: content, trigger: nil)
        )
    }
}
```

---

## Modify: project.yml

Add `Merlin/Connectors/PRMonitor.swift` to Merlin target sources.

```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'Test.*passed|Test.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```

Expected: `BUILD SUCCEEDED`; `PRMonitorTests` → 9 tests pass; all prior tests pass.

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/Connectors/PRMonitor.swift \
        project.yml
git commit -m "Phase 42b — PRMonitor: GitHub polling + CI status + auto-merge"
```
