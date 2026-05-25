import XCTest
@testable import Merlin

/// Task 309a — failing tests for ReachabilityScanner.
final class ReachabilityScannerTests: XCTestCase {

    /// Writes `[filename: content]` into a fresh temp project directory.
    private func makeTmpProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reachscan-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            try content.write(to: dir.appendingPathComponent(name),
                              atomically: true, encoding: .utf8)
        }
        return dir
    }

    func testDeadViewAndUninjectedEnvObjectAreFlagged() async throws {
        let proj = try makeTmpProject([
            "DeadView.swift": """
            import SwiftUI
            struct DeadView: View {
                var body: some View { Text("never shown") }
            }
            """,
            "ScreenView.swift": """
            import SwiftUI
            struct ScreenView: View {
                @EnvironmentObject var model: GhostModel
                var body: some View { Text("screen") }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await ReachabilityScanner().scan(projectPath: proj.path)
        XCTAssertTrue(findings.contains {
            $0.symbol == "DeadView" && $0.kind == "view-never-instantiated"
        }, "a View referenced by no other source must be flagged")
        XCTAssertTrue(findings.contains {
            $0.symbol == "GhostModel" && $0.kind == "environment-object-not-injected"
        }, "an @EnvironmentObject type that is never injected must be flagged")
    }

    func testInjectedEnvironmentObjectIsNotFlagged() async throws {
        let proj = try makeTmpProject([
            "ChatModel.swift": "import SwiftUI\nfinal class ChatModel: ObservableObject {}",
            "ConsumerView.swift": """
            import SwiftUI
            struct ConsumerView: View {
                @EnvironmentObject var model: ChatModel
                var body: some View { Text("x") }
            }
            """,
            "RootView.swift": """
            import SwiftUI
            struct RootView: View {
                @StateObject private var model = ChatModel()
                var body: some View { ConsumerView().environmentObject(model) }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await ReachabilityScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains {
            $0.symbol == "ChatModel" && $0.kind == "environment-object-not-injected"
        }, "a type created as a @StateObject and injected must NOT be flagged")
    }
}
