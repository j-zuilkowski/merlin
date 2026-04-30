import XCTest
@testable import Merlin

final class CompletionRequestSamplingParamsTests: XCTestCase {

    // MARK: - Helpers

    private let testBaseURL = URL(string: "http://localhost:1234/v1")!

    private func makeRequest() -> CompletionRequest {
        CompletionRequest(model: "test-model", messages: [], stream: false)
    }

    private func encodeToJSON(_ request: CompletionRequest) throws -> [String: Any] {
        let data = try encodeRequest(request, baseURL: testBaseURL, model: "test-model")
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Field existence (compile-time failures without phase 123b)

    func testTopKFieldExists() {
        var req = makeRequest()
        req.topK = 40
        XCTAssertEqual(req.topK, 40)
    }

    func testTopPFieldExists() {
        var req = makeRequest()
        req.topP = 0.9
        XCTAssertEqual(req.topP, 0.9)
    }

    func testMinPFieldExists() {
        var req = makeRequest()
        req.minP = 0.05
        XCTAssertEqual(req.minP, 0.05)
    }

    func testRepeatPenaltyFieldExists() {
        var req = makeRequest()
        req.repeatPenalty = 1.1
        XCTAssertEqual(req.repeatPenalty, 1.1)
    }

    func testFrequencyPenaltyFieldExists() {
        var req = makeRequest()
        req.frequencyPenalty = 0.5
        XCTAssertEqual(req.frequencyPenalty, 0.5)
    }

    func testPresencePenaltyFieldExists() {
        var req = makeRequest()
        req.presencePenalty = 0.3
        XCTAssertEqual(req.presencePenalty, 0.3)
    }

    func testSeedFieldExists() {
        var req = makeRequest()
        req.seed = 42
        XCTAssertEqual(req.seed, 42)
    }

    func testStopFieldExists() {
        var req = makeRequest()
        req.stop = ["<|end|>", "\n\n"]
        XCTAssertEqual(req.stop, ["<|end|>", "\n\n"])
    }

    // MARK: - JSON serialization

    func testNilSamplingParamsOmittedFromJSON() throws {
        let json = try encodeToJSON(makeRequest())
        XCTAssertNil(json["top_k"],             "nil topK must not appear in JSON")
        XCTAssertNil(json["top_p"],             "nil topP must not appear in JSON")
        XCTAssertNil(json["min_p"],             "nil minP must not appear in JSON")
        XCTAssertNil(json["repeat_penalty"],    "nil repeatPenalty must not appear in JSON")
        XCTAssertNil(json["frequency_penalty"],  "nil frequencyPenalty must not appear in JSON")
        XCTAssertNil(json["presence_penalty"],   "nil presencePenalty must not appear in JSON")
        XCTAssertNil(json["seed"],              "nil seed must not appear in JSON")
        XCTAssertNil(json["stop"],              "nil stop must not appear in JSON")
    }

    func testTopKSerializedToJSON() throws {
        var req = makeRequest()
        req.topK = 40
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["top_k"] as? Int, 40)
    }

    func testTopPSerializedToJSON() throws {
        var req = makeRequest()
        req.topP = 0.9
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["top_p"] as? Double, 0.9)
    }

    func testMinPSerializedToJSON() throws {
        var req = makeRequest()
        req.minP = 0.05
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["min_p"] as? Double, 0.05)
    }

    func testRepeatPenaltySerializedToJSON() throws {
        var req = makeRequest()
        req.repeatPenalty = 1.15
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["repeat_penalty"] as? Double, 1.15)
    }

    func testFrequencyPenaltySerializedToJSON() throws {
        var req = makeRequest()
        req.frequencyPenalty = 0.4
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["frequency_penalty"] as? Double, 0.4)
    }

    func testPresencePenaltySerializedToJSON() throws {
        var req = makeRequest()
        req.presencePenalty = 0.2
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["presence_penalty"] as? Double, 0.2)
    }

    func testSeedSerializedToJSON() throws {
        var req = makeRequest()
        req.seed = 1234
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["seed"] as? Int, 1234)
    }

    func testStopSerializedToJSON() throws {
        var req = makeRequest()
        req.stop = ["<|end|>"]
        let json = try encodeToJSON(req)
        XCTAssertEqual(json["stop"] as? [String], ["<|end|>"])
    }

    // MARK: - AppSettings inference defaults

    func testAppSettingsInferenceTopKExists() {
        // Compile-time proof — fails to build without phase 123b.
        let _ = AppSettings.shared.inferenceTopK
    }

    func testApplyInferenceDefaultsFillsNilFields() {
        // When the request has nil fields and AppSettings has a default,
        // applyInferenceDefaults should fill them in.
        AppSettings.shared.inferenceTopK = 40
        AppSettings.shared.inferenceTopP = 0.95

        var req = makeRequest()
        // topK and topP are nil on the request
        XCTAssertNil(req.topK)
        XCTAssertNil(req.topP)

        AppSettings.shared.applyInferenceDefaults(to: &req)

        XCTAssertEqual(req.topK, 40)
        XCTAssertEqual(req.topP, 0.95)
    }

    func testApplyInferenceDefaultsDoesNotOverrideExplicitValues() {
        AppSettings.shared.inferenceTopK = 40

        var req = makeRequest()
        req.topK = 10  // explicit per-request override

        AppSettings.shared.applyInferenceDefaults(to: &req)

        // Explicit value must win over default.
        XCTAssertEqual(req.topK, 10)
    }
}
