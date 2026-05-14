import AppIntents
import XCTest
@testable import Merlin

@MainActor
final class AppIntentsSupportTests: XCTestCase {

    func test_supportExposesUserFacingIntentsBeyondMetadata() {
        let names = Set(MerlinAppIntentsSupport.userFacingIntentTypes.map { String(describing: $0) })

        XCTAssertTrue(names.contains("StartMerlinSessionIntent"))
        XCTAssertTrue(names.contains("SendMerlinPromptIntent"))
        XCTAssertFalse(names.contains("MerlinMetadataIntent"))
    }

    func test_startSessionIntentDelegatesToInjectedSessionAction() async throws {
        let handler = FakeAppIntentActionHandler()
        let previousHandler = MerlinAppIntentsSupport.actionHandler
        MerlinAppIntentsSupport.actionHandler = handler
        defer { MerlinAppIntentsSupport.actionHandler = previousHandler }

        let intent = StartMerlinSessionIntent()

        _ = try await intent.perform()

        XCTAssertEqual(handler.startSessionCallCount, 1)
        XCTAssertEqual(handler.providerClientCreationCount, 0)
    }

    func test_sendPromptRejectsEmptyPrompts() async {
        let handler = FakeAppIntentActionHandler()
        let previousHandler = MerlinAppIntentsSupport.actionHandler
        MerlinAppIntentsSupport.actionHandler = handler
        defer { MerlinAppIntentsSupport.actionHandler = previousHandler }

        var intent = SendMerlinPromptIntent()
        intent.prompt = "   "

        await XCTAssertThrowsErrorAsync(try await intent.perform())

        XCTAssertEqual(handler.sentPrompts, [])
        XCTAssertEqual(handler.providerClientCreationCount, 0)
    }

    func test_sendPromptDelegatesExactPromptText() async throws {
        let handler = FakeAppIntentActionHandler()
        let previousHandler = MerlinAppIntentsSupport.actionHandler
        MerlinAppIntentsSupport.actionHandler = handler
        defer { MerlinAppIntentsSupport.actionHandler = previousHandler }

        var intent = SendMerlinPromptIntent()
        intent.prompt = "Build the board"

        _ = try await intent.perform()

        XCTAssertEqual(handler.sentPrompts, ["Build the board"])
        XCTAssertEqual(handler.providerClientCreationCount, 0)
    }

    private func XCTAssertThrowsErrorAsync(
        _ expression: @autoclosure () async throws -> Any,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error to be thrown", file: file, line: line)
        } catch {
            // expected
        }
    }
}

@MainActor
final class FakeAppIntentActionHandler: MerlinAppIntentActionHandling {
    private(set) var startSessionCallCount = 0
    private(set) var sentPrompts: [String] = []
    private(set) var providerClientCreationCount = 0

    func startSession() async throws {
        startSessionCallCount += 1
    }

    func sendPrompt(_ prompt: String) async throws {
        sentPrompts.append(prompt)
    }
}
