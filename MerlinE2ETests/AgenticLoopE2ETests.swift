import Foundation
import XCTest
@testable import Merlin

final class AgenticLoopE2ETests: XCTestCase {
    @MainActor
    func testFullLoopWithRealDeepSeek() async throws {
        try skipUnlessLiveEnvironment()
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
            ?? KeychainManager.readAPIKey()
        else {
            throw XCTSkip("No API key")
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

        // Post-phase-145b: AgenticEngine resolves providers from a ProviderRegistry
        // via slot assignments - it no longer takes pro/flash/vision arguments.
        // See TestHelpers/EngineFactory.swift for the same construction with mocks.
        let pro = DeepSeekProvider(apiKey: key, model: "deepseek-v4-flash")
        let config = ProviderConfig(
            id: pro.id,
            displayName: pro.id,
            baseURL: pro.baseURL.absoluteString,
            model: pro.id,
            isEnabled: true,
            isLocal: false,
            supportsThinking: true,
            supportsVision: false,
            kind: .openAICompatible)
        let registry = ProviderRegistry(
            persistURL: URL(fileURLWithPath:
                "/tmp/merlin-e2e-registry-\(UUID().uuidString).json"),
            initialProviders: [config])
        registry.add(pro)
        registry.activeProviderID = pro.id

        let engine = AgenticEngine(
            slotAssignments: [.execute: pro.id, .reason: pro.id, .vision: pro.id],
            registry: registry,
            toolRouter: router,
            contextManager: ContextManager())

        var finalText = ""
        for await event in engine.send(userMessage:
            "Read \(tmpPath) and tell me what it says") {
            if case .text(let text) = event {
                finalText += text
            }
        }

        XCTAssertTrue(finalText.lowercased().contains("hello from e2e test"))
    }
}
