import XCTest
@testable import Merlin

@MainActor
final class AppStateXcalibreServerEndpointTests: XCTestCase {
    func testAppStateUsesConfiguredXcalibreServerURLForRAGClient() async throws {
        let previousURL = AppSettings.shared.kagXcalibreURL
        let previousToken = AppSettings.shared.xcalibreToken
        AppSettings.shared.kagXcalibreURL = "http://127.0.0.1:8083"
        AppSettings.shared.xcalibreToken = "test-token"
        defer {
            AppSettings.shared.kagXcalibreURL = previousURL
            AppSettings.shared.xcalibreToken = previousToken
        }

        let appState = AppState(projectPath: try makeProject().path)

        let baseURL = await appState.xcalibreClient.configuredBaseURLForTesting()
        XCTAssertEqual(baseURL, "http://127.0.0.1:8083")
    }

    func testAppStateFallsBackToDefaultXcalibreServerURLWhenUnset() async throws {
        let previousURL = AppSettings.shared.kagXcalibreURL
        let previousToken = AppSettings.shared.xcalibreToken
        AppSettings.shared.kagXcalibreURL = ""
        AppSettings.shared.xcalibreToken = "test-token"
        defer {
            AppSettings.shared.kagXcalibreURL = previousURL
            AppSettings.shared.xcalibreToken = previousToken
        }

        let appState = AppState(projectPath: try makeProject().path)

        let baseURL = await appState.xcalibreClient.configuredBaseURLForTesting()
        XCTAssertEqual(baseURL, XcalibreClient.defaultBaseURL())
    }

    private func makeProject() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("appstate-xcalibre-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }
}
