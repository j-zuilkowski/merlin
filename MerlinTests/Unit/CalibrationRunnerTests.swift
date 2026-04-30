import XCTest
@testable import Merlin

// MARK: - CalibrationRunnerTests

final class CalibrationRunnerTests: XCTestCase {

    // MARK: - Type existence

    func testCalibrationCategoryExists() {
        let _: CalibrationCategory = .reasoning
        let _: CalibrationCategory = .coding
        let _: CalibrationCategory = .instructionFollowing
        let _: CalibrationCategory = .summarization
    }

    func testCalibrationPromptExists() {
        let p = CalibrationPrompt(id: "r1", category: .reasoning, prompt: "Q?", systemPrompt: nil)
        XCTAssertEqual(p.id, "r1")
        XCTAssertEqual(p.category, .reasoning)
    }

    func testCalibrationPromptWithSystemPrompt() {
        let p = CalibrationPrompt(id: "c1", category: .coding, prompt: "Write code.", systemPrompt: "You are an expert.")
        XCTAssertEqual(p.systemPrompt, "You are an expert.")
    }

    func testCalibrationResponseExists() {
        let p = CalibrationPrompt(id: "t", category: .coding, prompt: "p", systemPrompt: nil)
        let r = CalibrationResponse(
            prompt: p,
            localResponse: "local answer",
            referenceResponse: "ref answer",
            localScore: 0.7,
            referenceScore: 0.9
        )
        XCTAssertEqual(r.localResponse, "local answer")
        XCTAssertEqual(r.referenceResponse, "ref answer")
    }

    func testCalibrationResponseScoreDelta() {
        let p = CalibrationPrompt(id: "t", category: .reasoning, prompt: "p", systemPrompt: nil)
        let r = CalibrationResponse(prompt: p, localResponse: "a", referenceResponse: "b",
                                    localScore: 0.7, referenceScore: 0.9)
        XCTAssertEqual(r.scoreDelta, 0.2, accuracy: 0.001)
    }

    func testCalibrationResponseNegativeDelta() {
        // Local occasionally beats reference — delta can be negative
        let p = CalibrationPrompt(id: "t", category: .reasoning, prompt: "p", systemPrompt: nil)
        let r = CalibrationResponse(prompt: p, localResponse: "a", referenceResponse: "b",
                                    localScore: 0.95, referenceScore: 0.80)
        XCTAssertLessThan(r.scoreDelta, 0)
    }

    func testCalibrationReportExists() {
        let report = CalibrationReport(
            localProviderID: "lmstudio",
            referenceProviderID: "anthropic",
            responses: [],
            advisories: [],
            generatedAt: Date()
        )
        XCTAssertEqual(report.localProviderID, "lmstudio")
        XCTAssertEqual(report.referenceProviderID, "anthropic")
    }

    func testCalibrationReportOverallScores() {
        let p = CalibrationPrompt(id: "t", category: .reasoning, prompt: "p", systemPrompt: nil)
        let r1 = CalibrationResponse(prompt: p, localResponse: "a", referenceResponse: "b",
                                     localScore: 0.6, referenceScore: 0.9)
        let r2 = CalibrationResponse(prompt: p, localResponse: "a", referenceResponse: "b",
                                     localScore: 0.8, referenceScore: 1.0)
        let report = CalibrationReport(localProviderID: "x", referenceProviderID: "y",
                                       responses: [r1, r2], advisories: [], generatedAt: Date())
        XCTAssertEqual(report.overallLocalScore, 0.7, accuracy: 0.001)
        XCTAssertEqual(report.overallReferenceScore, 0.95, accuracy: 0.001)
        XCTAssertEqual(report.overallDelta, 0.25, accuracy: 0.001)
    }

    func testCalibrationReportEmptyResponsesScoreZero() {
        let report = CalibrationReport(localProviderID: "x", referenceProviderID: "y",
                                       responses: [], advisories: [], generatedAt: Date())
        XCTAssertEqual(report.overallLocalScore, 0.0)
        XCTAssertEqual(report.overallReferenceScore, 0.0)
    }

    func testCalibrationReportResponsesByCategory() {
        let r = CalibrationPrompt(id: "r1", category: .reasoning, prompt: "p", systemPrompt: nil)
        let c = CalibrationPrompt(id: "c1", category: .coding, prompt: "p", systemPrompt: nil)
        let resp1 = CalibrationResponse(prompt: r, localResponse: "a", referenceResponse: "b",
                                        localScore: 0.6, referenceScore: 0.8)
        let resp2 = CalibrationResponse(prompt: c, localResponse: "a", referenceResponse: "b",
                                        localScore: 0.7, referenceScore: 0.85)
        let report = CalibrationReport(localProviderID: "x", referenceProviderID: "y",
                                       responses: [resp1, resp2], advisories: [], generatedAt: Date())
        XCTAssertEqual(report.responsesByCategory[.reasoning]?.count, 1)
        XCTAssertEqual(report.responsesByCategory[.coding]?.count, 1)
    }

    // MARK: - CalibrationSuite

    func testCalibrationSuiteDefaultExists() {
        let suite = CalibrationSuite.default
        XCTAssertGreaterThanOrEqual(suite.prompts.count, 15)
    }

    func testCalibrationSuiteCoversAllCategories() {
        let suite = CalibrationSuite.default
        let categories = Set(suite.prompts.map(\.category))
        XCTAssertTrue(categories.contains(.reasoning))
        XCTAssertTrue(categories.contains(.coding))
        XCTAssertTrue(categories.contains(.instructionFollowing))
        XCTAssertTrue(categories.contains(.summarization))
    }

    func testCalibrationSuiteAllIDsUnique() {
        let suite = CalibrationSuite.default
        let ids = suite.prompts.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "All CalibrationPrompt IDs must be unique")
    }

    func testCalibrationSuitePromptsNonEmpty() {
        let suite = CalibrationSuite.default
        for prompt in suite.prompts {
            XCTAssertFalse(prompt.prompt.isEmpty, "Prompt \(prompt.id) has empty text")
        }
    }

    func testCalibrationSuiteHasReasoningPrompts() {
        let suite = CalibrationSuite.default
        let count = suite.prompts.filter { $0.category == .reasoning }.count
        XCTAssertGreaterThanOrEqual(count, 3, "Need at least 3 reasoning prompts for variance detection")
    }

    // MARK: - CalibrationRunner

    func testCalibrationRunnerExists() {
        let runner = CalibrationRunner(
            localProvider: { _ in "local" },
            referenceProvider: { _ in "ref" },
            scorer: { _, _ in 0.8 }
        )
        XCTAssertNotNil(runner)
    }

    func testCalibrationRunnerRunReturnsOneResponsePerPrompt() async throws {
        let runner = CalibrationRunner(
            localProvider: { _ in "local" },
            referenceProvider: { _ in "ref" },
            scorer: { _, _ in 0.75 }
        )
        let suite = CalibrationSuite(prompts: [
            CalibrationPrompt(id: "p1", category: .reasoning, prompt: "Q1", systemPrompt: nil),
            CalibrationPrompt(id: "p2", category: .coding, prompt: "Q2", systemPrompt: nil),
        ])
        let responses = try await runner.run(suite: suite)
        XCTAssertEqual(responses.count, 2)
    }

    func testCalibrationRunnerCapturesProviderResponses() async throws {
        let runner = CalibrationRunner(
            localProvider: { _ in "local answer" },
            referenceProvider: { _ in "ref answer" },
            scorer: { _, _ in 0.8 }
        )
        let suite = CalibrationSuite(prompts: [
            CalibrationPrompt(id: "p1", category: .reasoning, prompt: "Q1", systemPrompt: nil),
        ])
        let responses = try await runner.run(suite: suite)
        XCTAssertEqual(responses.first?.localResponse, "local answer")
        XCTAssertEqual(responses.first?.referenceResponse, "ref answer")
    }

    func testCalibrationRunnerScoresEachResponseTwice() async throws {
        // scorer is called once for local response and once for reference response per prompt
        actor Counter { var n = 0; func inc() { n += 1 } }
        let counter = Counter()
        let runner = CalibrationRunner(
            localProvider: { _ in "local" },
            referenceProvider: { _ in "ref" },
            scorer: { _, _ in
                await counter.inc()
                return 0.7
            }
        )
        let suite = CalibrationSuite(prompts: [
            CalibrationPrompt(id: "p1", category: .reasoning, prompt: "Q1", systemPrompt: nil),
            CalibrationPrompt(id: "p2", category: .coding, prompt: "Q2", systemPrompt: nil),
        ])
        _ = try await runner.run(suite: suite)
        let count = await counter.n
        XCTAssertEqual(count, 4, "scorer called once per response (local + ref) per prompt = 4 total")
    }

    func testCalibrationRunnerResultsOrderedByPromptID() async throws {
        let runner = CalibrationRunner(
            localProvider: { _ in "local" },
            referenceProvider: { _ in "ref" },
            scorer: { _, _ in 0.8 }
        )
        let suite = CalibrationSuite(prompts: [
            CalibrationPrompt(id: "z9", category: .coding, prompt: "Q", systemPrompt: nil),
            CalibrationPrompt(id: "a1", category: .reasoning, prompt: "Q", systemPrompt: nil),
            CalibrationPrompt(id: "m5", category: .summarization, prompt: "Q", systemPrompt: nil),
        ])
        let responses = try await runner.run(suite: suite)
        let ids = responses.map(\.prompt.id)
        XCTAssertEqual(ids, ids.sorted(), "Results must be sorted by prompt ID for deterministic UI display")
    }
}
