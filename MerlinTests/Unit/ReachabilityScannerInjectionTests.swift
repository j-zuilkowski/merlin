import XCTest
@testable import Merlin

/// Phase 317a — failing tests for ReachabilityScanner injection detection.
final class ReachabilityScannerInjectionTests: XCTestCase {

    private func makeTmpProject(_ files: [String: String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("reach-inject-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            try content.write(to: dir.appendingPathComponent(name),
                              atomically: true, encoding: .utf8)
        }
        return dir
    }

    /// A type owned by an annotation-only `@StateObject` (no inline constructor on the
    /// declaration line) and injected by property reference must NOT be flagged.
    func testAnnotationInjectedTypeIsNotFlagged() async throws {
        let proj = try makeTmpProject([
            "AppModel.swift": "import SwiftUI\nfinal class AppModel: ObservableObject {}",
            "ConsumerView.swift": """
            import SwiftUI
            struct ConsumerView: View {
                @EnvironmentObject var model: AppModel
                var body: some View { Text("x") }
            }
            """,
            "HostView.swift": """
            import SwiftUI
            struct HostView: View {
                @StateObject private var model: AppModel
                init() { _model = StateObject(wrappedValue: AppModel()) }
                var body: some View { ConsumerView().environmentObject(model) }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await ReachabilityScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains {
            $0.symbol == "AppModel" && $0.kind == "environment-object-not-injected"
        }, "a type owned by an annotation-only @StateObject must not be flagged")
    }

    func testProviderRegistryInjectedThroughAppStateRegistryIsNotFlagged() async throws {
        let proj = try makeTmpProject([
            "ProviderRegistry.swift": "import SwiftUI\nfinal class ProviderRegistry: ObservableObject {}",
            "AppState.swift": """
            import SwiftUI
            final class AppState: ObservableObject {
                let registry = ProviderRegistry()
            }
            """,
            "ConsumerView.swift": """
            import SwiftUI
            struct ConsumerView: View {
                @EnvironmentObject var registry: ProviderRegistry
                var body: some View { Text("x") }
            }
            """,
            "HostView.swift": """
            import SwiftUI
            struct HostView: View {
                @StateObject private var appState = AppState()
                var body: some View {
                    ConsumerView().environmentObject(appState.registry)
                }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await ReachabilityScanner().scan(projectPath: proj.path)

        XCTAssertFalse(findings.contains {
            $0.symbol == "ProviderRegistry" && $0.kind == "environment-object-not-injected"
        }, "appState.registry injection must satisfy ProviderRegistry consumers")
    }

    /// An `@EnvironmentObject` written inside a comment must not register a consumer.
    func testCommentDeclaredEnvObjectIsNotFlagged() async throws {
        let proj = try makeTmpProject([
            "RealView.swift": """
            import SwiftUI
            struct RealView: View {
                // Historically this used @EnvironmentObject var ghost: GhostModel
                var body: some View { Text("hi") }
            }
            """
        ])
        defer { try? FileManager.default.removeItem(at: proj) }

        let findings = await ReachabilityScanner().scan(projectPath: proj.path)
        XCTAssertFalse(findings.contains { $0.symbol == "GhostModel" },
                       "an @EnvironmentObject mentioned only in a comment is not a consumer")
    }
}
