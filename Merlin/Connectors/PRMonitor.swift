import AppKit
import Combine
import Foundation
import UserNotifications

struct RepoInfo: Sendable {
    var owner: String
    var repo: String
}

enum ChecksState: String, Codable, Sendable, Equatable {
    case pending
    case passed = "success"
    case failed = "failure"
    case error = "error"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ChecksState(rawValue: raw) ?? .unknown
    }
}

struct PRStatus: Decodable, Identifiable, Sendable {
    var id: Int { number }
    var number: Int
    var title: String
    var headSHA: String
    var checksState: ChecksState = .unknown
    var url: String

    enum CodingKeys: String, CodingKey {
        case number
        case title
        case head
        case url = "html_url"
    }

    struct Head: Decodable {
        var sha: String
    }

    init(number: Int,
         title: String,
         headSHA: String,
         checksState: ChecksState = .unknown,
         url: String) {
        self.number = number
        self.title = title
        self.headSHA = headSHA
        self.checksState = checksState
        self.url = url
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let head = try container.decode(Head.self, forKey: .head)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        headSHA = head.sha
    }
}

final class PRMonitor: ObservableObject {
    @Published private(set) var monitoredPRs: [PRStatus] = []
    @Published var autoMergeEnabled: Bool = false

    private var token: String = ""
    private var repoInfo: RepoInfo?
    private var pollTimer: Timer?
    private var observationTokens: [NSObjectProtocol] = []
    private let activeInterval: TimeInterval = 60
    private let backgroundInterval: TimeInterval = 300
    private var currentInterval: TimeInterval = 60

    func start(projectPath: String, token: String) {
        stop()
        self.token = token
        repoInfo = Self.detectRepoInfo(projectPath: projectPath)
        guard repoInfo != nil else { return }
        registerWorkspaceNotifications()
        schedulePolling(interval: activeInterval)
        Task { await poll() }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        observationTokens.forEach { NotificationCenter.default.removeObserver($0) }
        observationTokens.removeAll()
    }

    static func detectRepoInfo(projectPath: String) -> RepoInfo? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", projectPath, "remote", "-v"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        guard (try? process.run()) != nil else {
            return nil
        }
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parseRepoInfo(from: output)
    }

    static func parseRepoInfo(from remoteOutput: String) -> RepoInfo? {
        for rawLine in remoteOutput.split(separator: "\n") {
            let line = String(rawLine)
            if let repo = parseGitHubRemote(line, marker: "https://github.com/") {
                return repo
            }
            if let repo = parseGitHubRemote(line, marker: "git@github.com:") {
                return repo
            }
        }
        return nil
    }

    private static func parseGitHubRemote(_ line: String, marker: String) -> RepoInfo? {
        guard let start = line.range(of: marker)?.upperBound else {
            return nil
        }
        let remainder = line[start...]
        let repoSegment = remainder
            .split(whereSeparator: { $0 == " " || $0 == "(" })
            .first
            .map(String.init) ?? ""
        let trimmed = repoSegment.replacingOccurrences(of: ".git", with: "")
        let parts = trimmed.split(separator: "/")
        guard parts.count >= 2 else {
            return nil
        }
        return RepoInfo(owner: String(parts[0]), repo: String(parts[1]))
    }

    private func registerWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        let activate = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.schedulePolling(interval: self?.activeInterval ?? 60)
        }
        let deactivate = center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.schedulePolling(interval: self?.backgroundInterval ?? 300)
        }
        observationTokens = [activate, deactivate]
    }

    private func schedulePolling(interval: TimeInterval) {
        guard currentInterval != interval || pollTimer == nil else {
            return
        }
        currentInterval = interval
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.poll()
            }
        }
    }

    private func poll() async {
        guard let repoInfo else { return }
        let prs = await fetchOpenPRs(info: repoInfo)
        let previousStates = await MainActor.run {
            Dictionary(uniqueKeysWithValues: monitoredPRs.map { ($0.number, $0.checksState) })
        }
        let shouldAutoMerge = await MainActor.run { autoMergeEnabled }

        var updated: [PRStatus] = []
        for var pr in prs {
            pr.checksState = await fetchChecksState(info: repoInfo, sha: pr.headSHA)
            updated.append(pr)
        }

        await MainActor.run {
            monitoredPRs = updated
        }

        for pr in updated {
            let previous = previousStates[pr.number]
            if pr.checksState == .failed, previous != .failed {
                postFailureNotification(pr: pr)
            } else if pr.checksState == .passed, previous != .passed, shouldAutoMerge {
                await mergePR(info: repoInfo, number: pr.number)
            }
        }
    }

    private func fetchOpenPRs(info: RepoInfo) async -> [PRStatus] {
        let urlString = "https://api.github.com/repos/\(info.owner)/\(info.repo)/pulls?state=open&per_page=20"
        guard let url = URL(string: urlString) else {
            return []
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else {
            return []
        }
        return (try? JSONDecoder().decode([PRStatus].self, from: data)) ?? []
    }

    private func fetchChecksState(info: RepoInfo, sha: String) async -> ChecksState {
        let urlString = "https://api.github.com/repos/\(info.owner)/\(info.repo)/commits/\(sha)/status"
        guard let url = URL(string: urlString) else {
            return .unknown
        }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONDecoder().decode([String: JSONValue].self, from: data),
              let stateValue = json["state"],
              case .string(let state) = stateValue
        else {
            return .unknown
        }
        return ChecksState(rawValue: state) ?? .unknown
    }

    private func mergePR(info: RepoInfo, number: Int) async {
        let urlString = "https://api.github.com/repos/\(info.owner)/\(info.repo)/pulls/\(number)/merge"
        guard let url = URL(string: urlString) else {
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(["merge_method": "squash"])
        _ = try? await URLSession.shared.data(for: request)
    }

    private func postFailureNotification(pr: PRStatus) {
        let content = UNMutableNotificationContent()
        content.title = "CI Failed - PR #\(pr.number)"
        content.body = pr.title
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "pr-fail-\(pr.number)",
                content: content,
                trigger: nil
            )
        )
    }
}
