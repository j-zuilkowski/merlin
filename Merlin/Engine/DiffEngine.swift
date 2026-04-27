import Foundation

enum DiffLine: Equatable, Sendable {
    case context(String)
    case added(String)
    case removed(String)
}

struct DiffHunk: Identifiable, Sendable {
    var id: UUID = UUID()
    var lines: [DiffLine]

    var addedCount: Int {
        lines.filter { if case .added = $0 { true } else { false } }.count
    }

    var removedCount: Int {
        lines.filter { if case .removed = $0 { true } else { false } }.count
    }
}

enum DiffEngine {
    static func diff(before: String, after: String, contextLines: Int = 3) -> [DiffHunk] {
        let lhs = before.isEmpty ? [] : before.components(separatedBy: "\n")
        let rhs = after.isEmpty ? [] : after.components(separatedBy: "\n")

        if lhs.isEmpty && rhs.isEmpty {
            return []
        }

        let lines = buildLines(lhs: lhs, rhs: rhs)
        return lines.isEmpty ? [] : [DiffHunk(lines: lines)]
    }

    private static func buildLines(lhs: [String], rhs: [String]) -> [DiffLine] {
        let m = lhs.count
        let n = rhs.count
        guard m > 0 || n > 0 else {
            return []
        }

        var dp = Array(repeating: Array(repeating: 0, count: n + 1), count: m + 1)
        if m > 0 && n > 0 {
            for i in stride(from: m - 1, through: 0, by: -1) {
                for j in stride(from: n - 1, through: 0, by: -1) {
                    dp[i][j] = lhs[i] == rhs[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }

        var lines: [DiffLine] = []
        var i = 0
        var j = 0

        while i < m && j < n {
            if lhs[i] == rhs[j] {
                lines.append(.context(lhs[i]))
                i += 1
                j += 1
            } else if dp[i + 1][j] >= dp[i][j + 1] {
                lines.append(.removed(lhs[i]))
                i += 1
            } else {
                lines.append(.added(rhs[j]))
                j += 1
            }
        }

        while i < m {
            lines.append(.removed(lhs[i]))
            i += 1
        }

        while j < n {
            lines.append(.added(rhs[j]))
            j += 1
        }

        return lines
    }
}
