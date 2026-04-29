import Foundation
import CryptoKit

// MARK: - OutcomeSignals

/// Auto-collected at session end - no user action required.
struct OutcomeSignals: Sendable {
    var stage1Passed: Bool?           // nil = Stage 1 skipped (NullVerificationBackend)
    var stage2Score: Double?          // reason-slot critic score 0.0-1.0; nil = critic skipped
    var diffAccepted: Bool            // true = accepted as-is or with edits
    var diffEditedOnAccept: Bool      // true = user edited before accepting
    var criticRetryCount: Int         // feedback loops before pass
    var userCorrectedNextTurn: Bool   // heuristic: next message is a correction
    var sessionCompleted: Bool        // false = new session without task completion
    var addendumHash: String          // SHA256 of the provider's system_prompt_addendum
}

// MARK: - OutcomeRecord

struct OutcomeRecord: Codable, Sendable {
    var modelID: String
    var taskType: DomainTaskType
    var score: Double
    var addendumHash: String
    var timestamp: Date
}

// MARK: - Trend

enum Trend: String, Codable, Sendable {
    case improving
    case stable
    case declining
}

// MARK: - ModelPerformanceProfile

struct ModelPerformanceProfile: Codable, Sendable {
    var modelID: String
    var taskType: DomainTaskType
    var addendumHash: String
    var successRate: Double
    var sampleCount: Int
    var trend: Trend
    var lastUpdated: Date

    var isCalibrated: Bool { sampleCount >= 30 }
}

// MARK: - ModelPerformanceTracker

/// Builds empirical per-model × domain × task-type performance profiles from observed outcomes.
/// The 30-sample minimum ensures routing decisions are based on real data, not guesses.
///
/// Profile files: ~/.merlin/performance/<model-id>.json
actor ModelPerformanceTracker {

    private var profiles: [String: ModelPerformanceProfile] = [:]
    private var records: [String: [OutcomeRecord]] = [:]
    private let storageURL: URL
    private static let calibrationMinimum = 30
    private static let decayFactor = 0.9

    static let shared = ModelPerformanceTracker(
        storageURL: URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".merlin/performance")
    )

    init(storageURL: URL) {
        self.storageURL = storageURL
        profiles = Self.loadProfiles(from: storageURL)
    }

    // MARK: - Public API

    func record(modelID: String, taskType: DomainTaskType, signals: OutcomeSignals) async {
        let key = profileKey(modelID: modelID, taskType: taskType, addendumHash: signals.addendumHash)
        let score = computeScore(from: signals)
        let record = OutcomeRecord(
            modelID: modelID,
            taskType: taskType,
            score: score,
            addendumHash: signals.addendumHash,
            timestamp: Date()
        )

        records[key, default: []].append(record)
        updateProfile(
            key: key,
            modelID: modelID,
            taskType: taskType,
            addendumHash: signals.addendumHash,
            newScore: score
        )
        saveToDisk(modelID: modelID)
    }

    /// Returns nil until sampleCount >= 30 (calibration minimum).
    func successRate(for modelID: String, taskType: DomainTaskType) -> Double? {
        let matching = profiles.values.filter {
            $0.modelID == modelID && $0.taskType == taskType && $0.isCalibrated
        }
        return matching.max(by: { $0.sampleCount < $1.sampleCount })?.successRate
    }

    func profile(for modelID: String) -> [ModelPerformanceProfile] {
        profiles.values.filter { $0.modelID == modelID }
    }

    func allProfiles() -> [ModelPerformanceProfile] {
        Array(profiles.values)
    }

    // MARK: - Score computation

    private func computeScore(from signals: OutcomeSignals) -> Double {
        var score = 0.0
        var totalWeight = 0.0

        if let s1 = signals.stage1Passed {
            score += (s1 ? 1.0 : 0.0) * 3.0
            totalWeight += 3.0
        }

        if let s2 = signals.stage2Score {
            score += s2 * 3.0
            totalWeight += 3.0
        }

        let accepted = signals.diffAccepted ? 1.0 : 0.0
        score += accepted * 3.0
        totalWeight += 3.0

        if signals.diffEditedOnAccept {
            score += 0.5 * 2.0
            totalWeight += 2.0
        }

        let retryScore = max(0.0, 1.0 - Double(signals.criticRetryCount) * 0.25)
        score += retryScore * 2.0
        totalWeight += 2.0

        let correctedScore = signals.userCorrectedNextTurn ? 0.0 : 1.0
        score += correctedScore * 2.0
        totalWeight += 2.0

        score += (signals.sessionCompleted ? 1.0 : 0.5) * 1.0
        totalWeight += 1.0

        return totalWeight > 0 ? score / totalWeight : 0.5
    }

    // MARK: - Profile update

    private func updateProfile(key: String, modelID: String, taskType: DomainTaskType,
                               addendumHash: String, newScore: Double) {
        var profile = profiles[key] ?? ModelPerformanceProfile(
            modelID: modelID,
            taskType: taskType,
            addendumHash: addendumHash,
            successRate: newScore,
            sampleCount: 0,
            trend: .stable,
            lastUpdated: Date()
        )

        let prevRate = profile.successRate
        profile.successRate = profile.sampleCount == 0
            ? newScore
            : profile.successRate * Self.decayFactor + newScore * (1 - Self.decayFactor)
        profile.sampleCount += 1
        profile.lastUpdated = Date()
        profile.trend = computeTrend(prev: prevRate, current: profile.successRate)

        profiles[key] = profile
    }

    private func computeTrend(prev: Double, current: Double) -> Trend {
        let delta = current - prev
        if delta > 0.02 { return .improving }
        if delta < -0.02 { return .declining }
        return .stable
    }

    // MARK: - Persistence

    private func profileKey(modelID: String, taskType: DomainTaskType, addendumHash: String) -> String {
        "\(modelID)|\(taskType.domainID)|\(taskType.name)|\(addendumHash)"
    }

    private func saveToDisk(modelID: String) {
        let modelProfiles = profiles.values.filter { $0.modelID == modelID }
        guard !modelProfiles.isEmpty else { return }

        let sanitised = modelID.replacingOccurrences(of: "/", with: "_")
        let fileURL = storageURL.appendingPathComponent("\(sanitised).json")

        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(Array(modelProfiles)) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func loadProfiles(from storageURL: URL) -> [String: ModelPerformanceProfile] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storageURL, includingPropertiesForKeys: nil
        ) else { return [:] }

        var loadedProfiles: [String: ModelPerformanceProfile] = [:]

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let loaded = try? JSONDecoder().decode([ModelPerformanceProfile].self, from: data)
            else { continue }

            for p in loaded {
                let key = "\(p.modelID)|\(p.taskType.domainID)|\(p.taskType.name)|\(p.addendumHash)"
                loadedProfiles[key] = p
            }
        }

        return loadedProfiles
    }
}

// MARK: - Addendum hash helper

extension String {
    /// 8-character SHA256 hex prefix used to track which addendum variant produced an outcome.
    var addendumHash: String {
        guard !isEmpty else { return "00000000" }
        let data = Data(utf8)
        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(8))
    }
}
