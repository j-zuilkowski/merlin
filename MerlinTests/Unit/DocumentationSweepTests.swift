import XCTest

final class DocumentationSweepTests: XCTestCase {

    func testReleaseDocsMentionLlamaCppProvider() throws {
        let files = [
            "README.md",
            "FEATURES.md",
            "Merlin/Docs/UserGuide.md",
            "Merlin/Docs/DeveloperManual.md",
            "docs/local-provider-configs/README.md",
        ]
        for path in files {
            let text = try repoFile(path)
            XCTAssertTrue(
                text.localizedCaseInsensitiveContains("llama.cpp") ||
                text.localizedCaseInsensitiveContains("llamacpp"),
                "\(path) should mention llama.cpp/llamacpp"
            )
        }
        if let devGuide = try repoFileIfExists("docs/developer-guide.md") {
            XCTAssertTrue(
                devGuide.localizedCaseInsensitiveContains("llama.cpp") ||
                devGuide.localizedCaseInsensitiveContains("llamacpp"),
                "docs/developer-guide.md should mention llama.cpp/llamacpp when present"
            )
        }
    }

    func testLocalProviderScriptsKnowLlamaCpp() throws {
        let smoke = try repoFile("docs/local-provider-configs/smoke-test.sh")
        let benchmark = try repoFile("docs/local-provider-configs/benchmark-throughput.sh")

        XCTAssertTrue(smoke.contains("llamacpp"))
        XCTAssertTrue(benchmark.contains("llamacpp"))
        XCTAssertTrue(smoke.contains("http://localhost:8081/v1"))
        XCTAssertTrue(benchmark.contains("http://localhost:8081/v1"))
    }

    func testUserFacingDocsDoNotDescribeProviderHUDAsRoutingControl() throws {
        let docs = try [
            repoFile("README.md"),
            repoFile("FEATURES.md"),
            repoFile("Merlin/Docs/UserGuide.md"),
            repoFile("Merlin/Docs/DeveloperManual.md"),
        ].joined(separator: "\n")

        XCTAssertFalse(docs.localizedCaseInsensitiveContains("ProviderHUD"))
        XCTAssertFalse(docs.localizedCaseInsensitiveContains("top-of-chat"))
        XCTAssertFalse(docs.localizedCaseInsensitiveContains("top of the chat"))
    }

    func testUserFacingDocsDescribeSlotStatusPanel() throws {
        let docs = try [
            repoFile("FEATURES.md"),
            repoFile("Merlin/Docs/UserGuide.md"),
        ].joined(separator: "\n")

        XCTAssertTrue(docs.localizedCaseInsensitiveContains("Slot Status"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("Not configured"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("orange"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("red"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("grey"))
    }

    func testMainSurfaceRetiredIndicatorsStayRemoved() throws {
        let source = try [
            repoFile("Merlin/Views/ChatView.swift"),
            repoFile("Merlin/Views/ContentView.swift"),
            repoFile("Merlin/Views/SessionSidebar.swift"),
            repoFile("Merlin/Support/AccessibilityID.swift"),
        ].joined(separator: "\n")

        XCTAssertFalse(source.contains("chatPermissionModeButton"))
        XCTAssertFalse(source.contains("activeDomainIndicator"))
        XCTAssertFalse(source.contains("providerHUD"))
        XCTAssertFalse(source.contains("PermissionModeBadge"))
        XCTAssertFalse(source.contains("ToolbarItem(placement: .status)"))
    }

    func testEvalCurrentDocsUseUpdatedProviderCounts() throws {
        let docs = try [
            repoFile("merlin-eval/scenarios/S13-providers-connectors.md"),
            repoFile("merlin-eval/SURFACE-CENSUS.md"),
            repoFile("merlin-eval/SURFACE-INVENTORY.md"),
            repoFile("phases/SURFACE-INVENTORY.md"),
        ].joined(separator: "\n")

        XCTAssertFalse(docs.contains("11 providers"))
    }

    func testCurrentSurfaceDocsMentionSlotStatusPanel() throws {
        let docs = try [
            repoFile("merlin-eval/SURFACE-CENSUS.md"),
            repoFile("merlin-eval/SURFACE-INVENTORY.md"),
            repoFile("merlin-eval/scenarios/S9-panels.md"),
            repoFile("phases/SURFACE-INVENTORY.md"),
        ].joined(separator: "\n")

        XCTAssertTrue(docs.contains("SlotStatusPanel"))
        XCTAssertFalse(docs.contains("ProviderHUD"))
    }

    private func repoFile(_ path: String) throws -> String {
        let url = repoRootURL().appendingPathComponent(path)
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func repoFileIfExists(_ path: String) throws -> String? {
        let url = repoRootURL().appendingPathComponent(path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func repoRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Unit
            .deletingLastPathComponent() // MerlinTests
            .deletingLastPathComponent() // repo root
    }
}
