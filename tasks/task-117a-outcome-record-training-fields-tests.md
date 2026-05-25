# Phase 117a — OutcomeRecord Training Fields Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 116b complete: LoRA AppSettings in place.

Current state: OutcomeRecord has no prompt/response fields. The LoRATrainer (phase 118)
needs the actual conversation text to build training JSONL. The performanceTracker.record()
call in AgenticEngine passes only OutcomeSignals — no message text.

New surface introduced in phase 117b:
  - `OutcomeRecord.prompt: String` — the user message that triggered the session; default ""
    (backward compatible: old persisted records decode with "" for this field)
  - `OutcomeRecord.response: String` — the model's final text output; default ""
  - `ModelPerformanceTrackerProtocol.record(modelID:taskType:signals:prompt:response:)` —
    extended signature; backward-compatible default-parameter extension provides the old
    3-argument form so existing callers compile unchanged.
  - AgenticEngine.runLoop tracks `lastResponseText` (declared before the while loop,
    set when the loop exits without tool calls) and passes it with `userMessage` to record().

TDD coverage:
  File 1 — OutcomeRecordTrainingFieldsTests: prompt/response stored in record; old 3-arg
            record() call still compiles (backward compat); fields survive JSON round-trip;
            exportTrainingData only includes records with non-empty prompt + response;
            empty prompt/response records excluded from training export.

---

## Write to: MerlinTests/Unit/OutcomeRecordTrainingFieldsTests.swift

```swift
import XCTest
@testable import Merlin

final class OutcomeRecordTrainingFieldsTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("merlin-117-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    // MARK: - New fields exist on OutcomeRecord

    func testOutcomeRecordHasPromptField() {
        // BUILD FAILED until 117b adds OutcomeRecord.prompt
        let record = OutcomeRecord(
            modelID: "model-a",
            taskType: DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit"),
            score: 0.9,
            addendumHash: "abc123",
            timestamp: Date(),
            prompt: "Fix the crash in NetworkManager.swift",
            response: "The crash is caused by a force-unwrap on line 42."
        )
        XCTAssertEqual(record.prompt, "Fix the crash in NetworkManager.swift")
        XCTAssertEqual(record.response, "The crash is caused by a force-unwrap on line 42.")
    }

    // MARK: - Backward compatibility: old JSON (no prompt/response) decodes cleanly

    func testOutcomeRecordDecodesWithoutPromptResponse() throws {
        // Simulate a persisted record from before 117b (no prompt/response keys)
        let json = """
        {
            "modelID": "model-b",
            "taskType": {"domainID": "software", "name": "code-edit", "displayName": "Code Edit"},
            "score": 0.8,
            "addendumHash": "def456",
            "timestamp": 0
        }
        """.data(using: .utf8)!
        let record = try JSONDecoder().decode(OutcomeRecord.self, from: json)
        XCTAssertEqual(record.prompt, "")
        XCTAssertEqual(record.response, "")
    }

    // MARK: - Backward-compatible record() call (3-arg form still compiles)

    func testThreeArgRecordCallStillCompiles() async {
        let tracker = ModelPerformanceTracker(storageURL: tempDir)
        let taskType = DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit")
        let signals = OutcomeSignals(
            stage1Passed: true, stage2Score: 0.9,
            diffAccepted: true, diffEditedOnAccept: false,
            criticRetryCount: 0, userCorrectedNextTurn: false,
            sessionCompleted: true, addendumHash: "00000000"
        )
        // This must still compile unchanged — protocol extension provides the default.
        await tracker.record(modelID: "model-c", taskType: taskType, signals: signals)
        let records = await tracker.records(for: "model-c", taskType: taskType)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.prompt, "")
        XCTAssertEqual(records.first?.response, "")
    }

    // MARK: - Five-arg record() stores prompt and response

    func testFiveArgRecordStoresPromptAndResponse() async {
        let tracker = ModelPerformanceTracker(storageURL: tempDir)
        let taskType = DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit")
        let signals = OutcomeSignals(
            stage1Passed: true, stage2Score: 1.0,
            diffAccepted: true, diffEditedOnAccept: false,
            criticRetryCount: 0, userCorrectedNextTurn: false,
            sessionCompleted: true, addendumHash: "00000000"
        )
        await tracker.record(
            modelID: "model-d",
            taskType: taskType,
            signals: signals,
            prompt: "Refactor the login flow",
            response: "I've extracted the auth logic into AuthService."
        )
        let records = await tracker.records(for: "model-d", taskType: taskType)
        XCTAssertEqual(records.first?.prompt, "Refactor the login flow")
        XCTAssertEqual(records.first?.response, "I've extracted the auth logic into AuthService.")
    }

    // MARK: - exportTrainingData filters out empty prompt/response

    func testExportTrainingDataExcludesEmptyTextRecords() async {
        let tracker = ModelPerformanceTracker(storageURL: tempDir)
        let taskType = DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit")
        let goodSignals = OutcomeSignals(
            stage1Passed: true, stage2Score: 1.0,
            diffAccepted: true, diffEditedOnAccept: false,
            criticRetryCount: 0, userCorrectedNextTurn: false,
            sessionCompleted: true, addendumHash: "00000000"
        )

        // Record with text — qualifies
        await tracker.record(
            modelID: "model-e", taskType: taskType, signals: goodSignals,
            prompt: "Fix the bug", response: "Here is the fix."
        )
        // Record without text (old-style) — excluded from training export
        await tracker.record(
            modelID: "model-e", taskType: taskType, signals: goodSignals,
            prompt: "", response: ""
        )

        let exported = await tracker.exportTrainingData(minScore: 0.5)
        // Only the record with actual text should be in the training export
        XCTAssertEqual(exported.count, 1, "exportTrainingData must exclude records with empty prompt/response")
        XCTAssertEqual(exported.first?.prompt, "Fix the bug")
    }

    // MARK: - JSON round-trip preserves prompt and response

    func testOutcomeRecordJSONRoundTrip() throws {
        let record = OutcomeRecord(
            modelID: "model-f",
            taskType: DomainTaskType(domainID: "software", name: "code-edit", displayName: "Code Edit"),
            score: 0.95,
            addendumHash: "ghi789",
            timestamp: Date(timeIntervalSince1970: 1000),
            prompt: "Add unit tests for NetworkManager",
            response: "I've added 5 tests covering all public methods."
        )
        let data = try JSONEncoder().encode(record)
        let restored = try JSONDecoder().decode(OutcomeRecord.self, from: data)
        XCTAssertEqual(restored.prompt, record.prompt)
        XCTAssertEqual(restored.response, record.response)
    }
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `OutcomeRecord.prompt`, `OutcomeRecord.response` not defined;
`record(modelID:taskType:signals:prompt:response:)` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/OutcomeRecordTrainingFieldsTests.swift
git commit -m "Phase 117a — OutcomeRecordTrainingFieldsTests (failing)"
```
