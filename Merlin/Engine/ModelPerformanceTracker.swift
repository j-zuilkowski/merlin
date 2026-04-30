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
    /// The user message that triggered this session. Empty for records created before phase 117b.
    var prompt: String
    /// The model's final text response. Empty for records created before phase 117b.
    var response: String
    /// Marks records created via the legacy 3-argument record() path.
    var legacyTrainingRecord: Bool

    init(
        modelID: String,
        taskType: DomainTaskType,
        score: Double,
        addendumHash: String,
        timestamp: Date,
        prompt: String = "",
        response: String = "",
        legacyTrainingRecord: Bool = false
    ) {
        self.modelID = modelID
        self.taskType = taskType
        self.score = score
        self.addendumHash = addendumHash
        self.timestamp = timestamp
        self.prompt = prompt
        self.response = response
        self.legacyTrainingRecord = legacyTrainingRecord
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modelID = try c.decode(String.self, forKey: .modelID)
        taskType = try c.decode(DomainTaskType.self, forKey: .taskType)
        score = try c.decode(Double.self, forKey: .score)
        addendumHash = try c.decode(String.self, forKey: .addendumHash)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        response = (try? c.decode(String.self, forKey: .response)) ?? ""
        legacyTrainingRecord = (try? c.decode(Bool.self, forKey: .legacyTrainingRecord)) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modelID, forKey: .modelID)
        try c.encode(taskType, forKey: .taskType)
        try c.encode(score, forKey: .score)
        try c.encode(addendumHash, forKey: .addendumHash)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(prompt, forKey: .prompt)
        try c.encode(response, forKey: .response)
        try c.encode(legacyTrainingRecord, forKey: .legacyTrainingRecord)
    }

    private enum CodingKeys: String, CodingKey {
        case modelID
        case taskType
        case score
        case addendumHash
        case timestamp
        case prompt
        case response
        case legacyTrainingRecord
    }
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
/// Each OutcomeRecord includes prompt and response fields (captured by AgenticEngine from
/// userMessage and lastResponseText). exportTrainingData(minScore:) filters records with
/// empty prompt or response to ensure only records with actual training text enter the
/// LoRA pipeline.
///
/// Profile files: ~/.merlin/performance/<model-id>.json
/// Training data:  ~/.merlin/performance/records-<model-id>.json (persists across restarts)
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
        records = Self.loadRecords(from: storageURL)
    }

    // MARK: - Public API

    func record(
        modelID: String,
        taskType: DomainTaskType,
        signals: OutcomeSignals,
        prompt: String = "",
        response: String = "",
        legacyTrainingRecord: Bool = false
    ) async {
        let key = profileKey(modelID: modelID, taskType: taskType, addendumHash: signals.addendumHash)
        let score = computeScore(from: signals)
        let record = OutcomeRecord(
            modelID: modelID,
            taskType: taskType,
            score: score,
            addendumHash: signals.addendumHash,
            timestamp: Date(),
            prompt: prompt,
            response: response,
            legacyTrainingRecord: legacyTrainingRecord
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
        saveRecordsToDisk(modelID: modelID)
    }

    func record(
        modelID: String,
        taskType: DomainTaskType,
        signals: OutcomeSignals
    ) async {
        await record(
            modelID: modelID,
            taskType: taskType,
            signals: signals,
            prompt: "",
            response: "",
            legacyTrainingRecord: true
        )
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

    /// Returns all persisted OutcomeRecords for a given model + task type.
    /// Used by V6 LoRA training to build the fine-tuning dataset.
    func records(for modelID: String, taskType: DomainTaskType) async -> [OutcomeRecord] {
        records.values
            .flatMap { $0 }
            .filter { $0.modelID == modelID && $0.taskType == taskType }
            .sorted { $0.timestamp < $1.timestamp }
    }

    /// Returns all OutcomeRecords with score >= minScore across all models and task types.
    /// Records are included when:
    ///   - legacyTrainingRecord == true (created before V6 prompt/response capture), OR
    ///   - both prompt and response are non-empty (standard V6 records)
    /// This ensures the LoRA JSONL export always has valid user/assistant pairs.
    /// minScore: 0.0–1.0; recommended minimum 0.7 to exclude poor-quality examples.
    func exportTrainingData(minScore: Double) async -> [OutcomeRecord] {
        return records.values
            .flatMap { $0 }
            .filter { $0.score >= minScore && ($0.legacyTrainingRecord || (!$0.prompt.isEmpty && !$0.response.isEmpty)) }
            .sorted { $0.timestamp < $1.timestamp }
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

    private func saveRecordsToDisk(modelID: String) {
        let modelRecords = records.values
            .flatMap { $0 }
            .filter { $0.modelID == modelID }

        guard !modelRecords.isEmpty else { return }

        let sanitised = modelID.replacingOccurrences(of: "/", with: "_")
        let fileURL = storageURL.appendingPathComponent("records-\(sanitised).json")

        try? FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(modelRecords) {
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

    private static func loadRecords(from storageURL: URL) -> [String: [OutcomeRecord]] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: storageURL, includingPropertiesForKeys: nil
        ) else { return [:] }

        var loaded: [String: [OutcomeRecord]] = [:]

        for file in files where file.lastPathComponent.hasPrefix("records-") &&
                                 file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let fileRecords = try? JSONDecoder().decode([OutcomeRecord].self, from: data)
            else { continue }

            for record in fileRecords {
                let key = "\(record.modelID)|\(record.taskType.domainID)|\(record.taskType.name)|\(record.addendumHash)"
                loaded[key, default: []].append(record)
            }
        }

        return loaded.mapValues { records in
            Array(
                Dictionary(grouping: records, by: { $0.timestamp.timeIntervalSince1970 })
                    .values
                    .compactMap { $0.first }
            )
            .sorted { $0.timestamp < $1.timestamp }
        }
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
