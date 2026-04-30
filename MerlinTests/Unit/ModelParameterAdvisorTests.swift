import XCTest
@testable import Merlin

final class ModelParameterAdvisorTests: XCTestCase {

    // MARK: - Compile-time existence checks

    func testParameterAdvisoryKindExists() {
        // Fails to build without phase 124b.
        let _: ParameterAdvisoryKind = .maxTokensTooLow
        let _: ParameterAdvisoryKind = .temperatureUnstable
        let _: ParameterAdvisoryKind = .repetitiveOutput
        let _: ParameterAdvisoryKind = .contextLengthTooSmall
    }

    func testOutcomeSignalsFinishReasonFieldExists() {
        var signals = OutcomeSignals(
            stage1Passed: nil,
            stage2Score: nil,
            diffAccepted: false,
            diffEditedOnAccept: false,
            criticRetryCount: 0,
            userCorrectedNextTurn: false,
            sessionCompleted: true,
            addendumHash: ""
        )
        signals.finishReason = "length"
        XCTAssertEqual(signals.finishReason, "length")
    }

    // MARK: - checkRecord: truncation detection

    func testCheckRecordFinishReasonLengthProducesMaxTokensAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: "length", response: "This is a normal response")
        let advisories = await advisor.checkRecord(record)
        XCTAssertTrue(advisories.contains { $0.kind == .maxTokensTooLow },
                      "Expected .maxTokensTooLow advisory for finish_reason=length")
    }

    func testCheckRecordFinishReasonStopProducesNoTruncationAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: "stop", response: "This is a normal response")
        let advisories = await advisor.checkRecord(record)
        XCTAssertFalse(advisories.contains { $0.kind == .maxTokensTooLow },
                       "finish_reason=stop must not trigger maxTokensTooLow")
    }

    func testCheckRecordNilFinishReasonProducesNoTruncationAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: nil, response: "Normal response")
        let advisories = await advisor.checkRecord(record)
        XCTAssertFalse(advisories.contains { $0.kind == .maxTokensTooLow })
    }

    // MARK: - checkRecord: context overflow detection

    func testCheckRecordContextOverflowStringProducesContextAdvisory() async {
        let advisor = ModelParameterAdvisor()
        // LM Studio / llama.cpp returns this string when context is exceeded
        let record = makeRecord(
            finishReason: "stop",
            response: "context length exceeded — prompt truncated"
        )
        let advisories = await advisor.checkRecord(record)
        XCTAssertTrue(advisories.contains { $0.kind == .contextLengthTooSmall },
                      "Expected .contextLengthTooSmall advisory for context overflow response")
    }

    func testCheckRecordNormalResponseProducesNoContextAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: "stop", response: "Here is your code refactor.")
        let advisories = await advisor.checkRecord(record)
        XCTAssertFalse(advisories.contains { $0.kind == .contextLengthTooSmall })
    }

    // MARK: - analyze: score variance (temperature instability)

    func testAnalyzeHighScoreVarianceProducesTemperatureAdvisory() async {
        let advisor = ModelParameterAdvisor()
        // Alternating high/low scores produce high variance
        let records = (0..<10).map { i -> OutcomeRecord in
            makeRecord(score: i.isMultiple(of: 2) ? 0.95 : 0.10)
        }
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertTrue(advisories.contains { $0.kind == .temperatureUnstable },
                      "High score variance should trigger .temperatureUnstable")
    }

    func testAnalyzeLowVarianceProducesNoTemperatureAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let records = (0..<10).map { _ in makeRecord(score: 0.80) }
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertFalse(advisories.contains { $0.kind == .temperatureUnstable },
                       "Low variance must not trigger .temperatureUnstable")
    }

    func testAnalyzeTooFewRecordsSkipsVarianceCheck() async {
        // Need at least 5 records to compute meaningful variance.
        let advisor = ModelParameterAdvisor()
        let records = [makeRecord(score: 0.9), makeRecord(score: 0.1)]
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertFalse(advisories.contains { $0.kind == .temperatureUnstable },
                       "Fewer than 5 records must not trigger temperature advisory")
    }

    // MARK: - analyze: repetition detection

    func testAnalyzeRepetitiveResponseProducesRepetitionAdvisory() async {
        let advisor = ModelParameterAdvisor()
        // A response that repeats the same phrase many times
        let repetitive = Array(repeating: "the quick brown fox jumps over the lazy dog", count: 15)
            .joined(separator: " ")
        let records = (0..<5).map { _ in makeRecord(response: repetitive) }
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertTrue(advisories.contains { $0.kind == .repetitiveOutput },
                      "Highly repetitive responses should trigger .repetitiveOutput")
    }

    func testAnalyzeCleanResponseProducesNoRepetitionAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let clean = """
        This function uses async/await to handle concurrent operations. \
        The actor isolation ensures thread safety without manual locking. \
        Structured concurrency via TaskGroup lets child tasks run in parallel \
        and the parent awaits all results before proceeding.
        """
        let records = (0..<5).map { _ in makeRecord(response: clean) }
        let advisories = await advisor.analyze(records: records, modelID: "test-model")
        XCTAssertFalse(advisories.contains { $0.kind == .repetitiveOutput })
    }

    // MARK: - Advisory management

    func testDismissRemovesAdvisory() async {
        let advisor = ModelParameterAdvisor()
        let record = makeRecord(finishReason: "length", response: "truncated")
        let found = await advisor.checkRecord(record)
        guard let advisory = found.first else {
            XCTFail("Expected at least one advisory")
            return
        }
        await advisor.store(advisories: found, modelID: "test-model")
        await advisor.dismiss(advisory)
        let remaining = await advisor.currentAdvisories(for: "test-model")
        XCTAssertFalse(remaining.contains { $0.kind == advisory.kind && $0.modelID == advisory.modelID })
    }

    func testCurrentAdvisoriesFiltersByModelID() async {
        let advisor = ModelParameterAdvisor()
        let a1 = makeAdvisory(modelID: "model-A")
        let a2 = makeAdvisory(modelID: "model-B")
        await advisor.store(advisories: [a1], modelID: "model-A")
        await advisor.store(advisories: [a2], modelID: "model-B")

        let forA = await advisor.currentAdvisories(for: "model-A")
        XCTAssertTrue(forA.allSatisfy { $0.modelID == "model-A" })
        XCTAssertFalse(forA.contains { $0.modelID == "model-B" })
    }

    // MARK: - OutcomeRecord backward compatibility

    func testOutcomeRecordFinishReasonBackwardCompatDecode() throws {
        // JSON without finishReason field (old format) must decode without error,
        // with finishReason falling back to nil.
        let json = """
        {
          "modelID": "test-model",
          "taskType": "codeGeneration",
          "score": 0.75,
          "addendumHash": "abc123",
          "timestamp": "2026-04-30T00:00:00Z",
          "prompt": "write a function",
          "response": "func foo() {}",
          "legacyTrainingRecord": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let record = try decoder.decode(OutcomeRecord.self, from: json)
        XCTAssertNil(record.finishReason,
                     "finishReason must be nil when absent from JSON (backward compat)")
    }

    // MARK: - Helpers

    private func makeRecord(
        modelID: String = "test-model",
        score: Double = 0.75,
        finishReason: String? = nil,
        response: String = "This is a response."
    ) -> OutcomeRecord {
        let taskType = DomainTaskType(
            domainID: "test-domain",
            name: "code_generation",
            displayName: "Code Generation"
        )
        var record = OutcomeRecord(
            modelID: modelID,
            taskType: taskType,
            score: score,
            addendumHash: "",
            timestamp: Date(),
            prompt: "test prompt",
            response: response
        )
        record.finishReason = finishReason
        return record
    }

    private func makeAdvisory(modelID: String) -> ParameterAdvisory {
        ParameterAdvisory(
            kind: .maxTokensTooLow,
            parameterName: "maxTokens",
            currentValue: "1024",
            suggestedValue: "2048",
            explanation: "Responses are being truncated.",
            modelID: modelID,
            detectedAt: Date()
        )
    }
}
