import XCTest
@testable import Merlin

// MARK: - CalibrationAdvisorTests

final class CalibrationAdvisorTests: XCTestCase {

    // MARK: - Helpers

    private func makePrompt(id: String, category: CalibrationCategory) -> CalibrationPrompt {
        CalibrationPrompt(id: id, category: category, prompt: "Q?", systemPrompt: nil)
    }

    private func makeResponse(
        id: String,
        category: CalibrationCategory = .reasoning,
        localScore: Double,
        referenceScore: Double,
        localText: String = "answer",
        referenceText: String = "answer"
    ) -> CalibrationResponse {
        CalibrationResponse(
            prompt: makePrompt(id: id, category: category),
            localResponse: localText,
            referenceResponse: referenceText,
            localScore: localScore,
            referenceScore: referenceScore
        )
    }

    // MARK: - Type existence

    func testCalibrationAdvisorExists() {
        let _ = CalibrationAdvisor()
    }

    func testCategoryScoresExists() {
        let s = CategoryScores(localAverage: 0.7, referenceAverage: 0.9)
        XCTAssertEqual(s.delta, 0.2, accuracy: 0.001)
    }

    // MARK: - No advisory when gap is small

    func testNoAdvisoryWhenScoreGapBelowThreshold() {
        let advisor = CalibrationAdvisor()
        let responses = (0..<8).map { i in
            makeResponse(id: "p\(i)", localScore: 0.80, referenceScore: 0.90)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "model", localProviderID: "lmstudio")
        XCTAssertTrue(advisories.isEmpty, "Gap of 0.10 is below 0.15 threshold — no advisories expected")
    }

    func testNoAdvisoryForPerfectLocalScores() {
        let advisor = CalibrationAdvisor()
        let responses = (0..<8).map { i in
            makeResponse(id: "p\(i)", localScore: 0.95, referenceScore: 0.92)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "model", localProviderID: "lmstudio")
        XCTAssertTrue(advisories.isEmpty)
    }

    // MARK: - Context length advisory

    func testLargeConsistentDeltaProducesContextLengthAdvisory() {
        let advisor = CalibrationAdvisor()
        let responses = (0..<10).map { i in
            makeResponse(id: "p\(i)", localScore: 0.35, referenceScore: 0.85)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "qwen-72b", localProviderID: "lmstudio")
        let kinds = advisories.map(\.kind)
        XCTAssertTrue(kinds.contains(.contextLengthTooSmall),
                      "Delta of 0.50 should produce .contextLengthTooSmall advisory")
    }

    func testContextLengthAdvisoryContainsSuggestedValue() {
        let advisor = CalibrationAdvisor()
        let responses = (0..<10).map { i in
            makeResponse(id: "p\(i)", localScore: 0.30, referenceScore: 0.90)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "model", localProviderID: "lmstudio")
        let ctxAdvisory = advisories.first { $0.kind == .contextLengthTooSmall }
        XCTAssertNotNil(ctxAdvisory)
        XCTAssertFalse(ctxAdvisory?.suggestedValue.isEmpty ?? true)
    }

    // MARK: - Temperature advisory

    func testHighScoreVarianceProducesTemperatureAdvisory() {
        let advisor = CalibrationAdvisor()
        // Alternating high/low local scores → high variance (σ ≈ 0.30)
        let responses = (0..<8).map { i in
            makeResponse(id: "p\(i)", localScore: i.isMultiple(of: 2) ? 0.9 : 0.2, referenceScore: 0.80)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "model", localProviderID: "lmstudio")
        let kinds = advisories.map(\.kind)
        XCTAssertTrue(kinds.contains(.temperatureUnstable),
                      "High local score variance (σ > 0.22) should produce .temperatureUnstable")
    }

    func testStableScoresDoNotProduceTemperatureAdvisory() {
        let advisor = CalibrationAdvisor()
        let responses = (0..<8).map { i in
            makeResponse(id: "p\(i)", localScore: 0.72, referenceScore: 0.80)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "model", localProviderID: "lmstudio")
        let kinds = advisories.map(\.kind)
        XCTAssertFalse(kinds.contains(.temperatureUnstable))
    }

    // MARK: - Max tokens advisory

    func testTruncatedLocalResponsesProduceMaxTokensAdvisory() {
        let advisor = CalibrationAdvisor()
        let shortLocal = "Short."
        let longRef = String(repeating: "Reference response with full detail and complete reasoning. ", count: 20)
        let responses = (0..<6).map { i in
            makeResponse(id: "p\(i)", localScore: 0.4, referenceScore: 0.85,
                         localText: shortLocal, referenceText: longRef)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "model", localProviderID: "lmstudio")
        let kinds = advisories.map(\.kind)
        XCTAssertTrue(kinds.contains(.maxTokensTooLow),
                      "≥50% of local responses being significantly shorter should produce .maxTokensTooLow")
    }

    func testAdequateLengthDoesNotProduceMaxTokensAdvisory() {
        let advisor = CalibrationAdvisor()
        let local = String(repeating: "word ", count: 60)
        let ref = String(repeating: "word ", count: 70)
        let responses = (0..<6).map { i in
            makeResponse(id: "p\(i)", localScore: 0.75, referenceScore: 0.85,
                         localText: local, referenceText: ref)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "model", localProviderID: "lmstudio")
        let kinds = advisories.map(\.kind)
        XCTAssertFalse(kinds.contains(.maxTokensTooLow))
    }

    // MARK: - Repeat penalty advisory

    func testRepetitiveLocalResponsesProduceRepeatPenaltyAdvisory() {
        let advisor = CalibrationAdvisor()
        let repetitive = String(repeating: "The answer is correct and the answer is correct. ", count: 10)
        let clean = "A well-structured response with varied vocabulary covering several distinct points clearly."
        let responses = (0..<6).map { i in
            makeResponse(id: "p\(i)", category: .summarization, localScore: 0.35, referenceScore: 0.85,
                         localText: repetitive, referenceText: clean)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "model", localProviderID: "lmstudio")
        let kinds = advisories.map(\.kind)
        XCTAssertTrue(kinds.contains(.repetitiveOutput),
                      "≥50% repetitive local responses should produce .repetitiveOutput")
    }

    // MARK: - Advisory modelID

    func testAllAdvisoriesCarryLocalModelID() {
        let advisor = CalibrationAdvisor()
        let responses = (0..<10).map { i in
            makeResponse(id: "p\(i)", localScore: 0.30, referenceScore: 0.90)
        }
        let advisories = advisor.analyze(responses: responses, localModelID: "qwen2.5-vl-72b", localProviderID: "lmstudio")
        XCTAssertTrue(advisories.allSatisfy { $0.modelID == "qwen2.5-vl-72b" },
                      "All advisories must carry the local model ID")
    }

    // MARK: - Category breakdown

    func testCategoryBreakdownComputesPerCategoryAverages() {
        let advisor = CalibrationAdvisor()
        let p1 = makePrompt(id: "r1", category: .reasoning)
        let p2 = makePrompt(id: "c1", category: .coding)
        let responses = [
            CalibrationResponse(prompt: p1, localResponse: "a", referenceResponse: "b",
                                localScore: 0.5, referenceScore: 0.9),
            CalibrationResponse(prompt: p2, localResponse: "a", referenceResponse: "b",
                                localScore: 0.8, referenceScore: 0.85),
        ]
        let breakdown = advisor.categoryBreakdown(responses: responses)
        XCTAssertEqual(breakdown[.reasoning]?.localAverage ?? 0, 0.5, accuracy: 0.001)
        XCTAssertEqual(breakdown[.coding]?.localAverage ?? 0, 0.8, accuracy: 0.001)
        XCTAssertEqual(breakdown[.reasoning]?.delta ?? 0, 0.4, accuracy: 0.001)
    }

    func testCategoryBreakdownEmptyReturnsEmpty() {
        let advisor = CalibrationAdvisor()
        let breakdown = advisor.categoryBreakdown(responses: [])
        XCTAssertTrue(breakdown.isEmpty)
    }

    // MARK: - Empty input

    func testAnalyzeEmptyResponsesReturnsNoAdvisories() {
        let advisor = CalibrationAdvisor()
        let advisories = advisor.analyze(responses: [], localModelID: "model", localProviderID: "lmstudio")
        XCTAssertTrue(advisories.isEmpty)
    }
}
