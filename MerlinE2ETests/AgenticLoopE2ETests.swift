import Foundation
import XCTest
@testable import Merlin

final class AgenticLoopE2ETests: XCTestCase {
    @MainActor
    func testFullLoopWithRealDeepSeek() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_TESTS"] != nil,
              let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"] ?? KeychainManager.readAPIKey()
        else {
            throw XCTSkip("Live tests disabled or no API key")
        }

        let tmpPath = "/tmp/merlin-e2e-test.txt"
        try "hello from e2e test".write(toFile: tmpPath, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmpPath) }

        let memory = AuthMemory(storePath: "/dev/null")
        memory.addAllowPattern(tool: "read_file", pattern: "/tmp/**")
        let gate = AuthGate(memory: memory, presenter: NullAuthPresenter())
        let router = ToolRouter(authGate: gate)
        router.register(name: "read_file") { args in
            struct PathArgs: Decodable { var path: String }
            let decoded = try JSONDecoder().decode(PathArgs.self, from: Data(args.utf8))
            return try await FileSystemTools.readFile(path: decoded.path)
        }

        let pro = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
        let engine = AgenticEngine(
            proProvider: pro,
            flashProvider: pro,
            visionProvider: LMStudioProvider(),
            toolRouter: router,
            contextManager: ContextManager()
        )

        var finalText = ""
        for await event in engine.send(userMessage: "Read \(tmpPath) and tell me what it says") {
            if case .text(let text) = event {
                finalText += text
            }
        }

        XCTAssertTrue(finalText.lowercased().contains("hello from e2e test"))
    }
}
