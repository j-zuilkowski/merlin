import Foundation
import XCTest
@testable import Merlin

final class AgenticLoopE2ETests: XCTestCase {
    @MainActor
    func testFullLoopWithRealDeepSeek() async throws {
        try skipUnlessLiveEnvironment()
        // KeychainManager.readAPIKey() (no-arg) resolves the dead "deepseek-legacy"
        // provider ID; Merlin actually stores the key under "deepseek" / "deepseek-flash"
        // in ~/.merlin/api-keys.json. Read those — the real key store.
        guard let key = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]
            ?? KeychainManager.readAPIKey(for: "deepseek")
            ?? KeychainManager.readAPIKey(for: "deepseek-flash")
        else {
            throw XCTSkip("No DeepSeek API key in ~/.merlin/api-keys.json or Keychain")
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
        // The engine advertises tool *schemas* to the LLM from ToolRegistry.shared
        // (AgenticEngine builds request.tools from it). Registering an executor on the
        // router is not enough — without the schema the model is never offered the
        // tool and just answers in prose. Register read_file's definition too.
        ToolRegistry.shared.register(ToolDefinitions.readFile)

        // Post-task-145b: AgenticEngine resolves providers from a ProviderRegistry
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
        var diagnostics: [String] = []
        for await event in engine.send(userMessage:
            "Read \(tmpPath) and tell me what it says") {
            switch event {
            case .text(let text):
                finalText += text
            case .error(let err):
                diagnostics.append("ERROR: \(String(describing: err))")
            case .systemNote(let note):
                diagnostics.append("NOTE: \(note)")
            case .toolCallStarted(let call):
                diagnostics.append("TOOL-START: \(String(describing: call))")
            case .toolCallResult(let result):
                diagnostics.append("TOOL-RESULT: \(String(describing: result))")
            default:
                diagnostics.append("EVENT: \(String(describing: event))")
            }
        }

        let report = "finalText=[\(finalText)]\nevents:\n" + diagnostics.joined(separator: "\n")
        XCTAssertTrue(finalText.lowercased().contains("hello from e2e test"),
                      "AgenticLoop did not echo the file content.\n\(report)")
    }
}
