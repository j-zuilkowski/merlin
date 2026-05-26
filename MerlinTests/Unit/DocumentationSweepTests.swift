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
            repoFile("tasks/SURFACE-INVENTORY.md"),
        ].joined(separator: "\n")

        XCTAssertFalse(docs.contains("11 providers"))
    }

    func testCurrentSurfaceDocsMentionSlotStatusPanel() throws {
        let docs = try [
            repoFile("merlin-eval/SURFACE-CENSUS.md"),
            repoFile("merlin-eval/SURFACE-INVENTORY.md"),
            repoFile("merlin-eval/scenarios/S9-panels.md"),
            repoFile("tasks/SURFACE-INVENTORY.md"),
        ].joined(separator: "\n")

        XCTAssertTrue(docs.contains("SlotStatusPanel"))
        XCTAssertFalse(docs.contains("ProviderHUD"))
    }


    func testReleaseDocsMentionCAG() throws {
        let docs = try [
            repoFile("FEATURES.md"),
            repoFile("Merlin/Docs/UserGuide.md"),
            repoFile("Merlin/Docs/DeveloperManual.md"),
        ].joined(separator: "\n")

        XCTAssertTrue(
            docs.localizedCaseInsensitiveContains("cache-augmented generation") ||
            docs.localizedCaseInsensitiveContains("cag"),
            "Release-current docs should mention CAG"
        )
    }

    func testReleaseDocsDoNotCallCAGPlanned() throws {
        let docs = try [
            repoFile("FEATURES.md"),
            repoFile("Merlin/Docs/UserGuide.md"),
            repoFile("Merlin/Docs/DeveloperManual.md"),
        ].joined(separator: "\n")

        XCTAssertFalse(docs.localizedCaseInsensitiveContains("cag planned"))
        XCTAssertFalse(docs.localizedCaseInsensitiveContains("cache-augmented generation planned"))
        XCTAssertFalse(docs.localizedCaseInsensitiveContains("cag not implemented"))
        XCTAssertFalse(docs.localizedCaseInsensitiveContains("cache-augmented generation not implemented"))

        XCTAssertTrue(docs.localizedCaseInsensitiveContains("cache_control"))
        XCTAssertTrue(
            docs.localizedCaseInsensitiveContains("stable prefix bytes") ||
            docs.localizedCaseInsensitiveContains("stable-byte") ||
            docs.localizedCaseInsensitiveContains("automatic cache behavior"),
            "Release-current docs should distinguish Anthropic explicit markers from stable-prefix behavior elsewhere"
        )
    }

    func testDocsDescribeSDDTraceabilityAsImplemented() throws {
        let docs = try [
            repoFile("FEATURES.md"),
            repoFile("Merlin/Docs/UserGuide.md"),
            repoFile("Merlin/Docs/DeveloperManual.md"),
            repoFile("spec.md"),
            repoFile("vision.md"),
        ].joined(separator: "\n")

        XCTAssertTrue(docs.contains("SDDTraceabilityScanner"))
        XCTAssertTrue(docs.contains("sddTraceability"))
        XCTAssertTrue(docs.contains("## Behavior"))
        XCTAssertTrue(docs.contains("## Traceability"))
        XCTAssertFalse(docs.localizedCaseInsensitiveContains(
            "sdd rename as deferred"))
        XCTAssertFalse(docs.localizedCaseInsensitiveContains(
            "structural rename and should only be promoted"))
    }

    func testElectronicsDocsDescribeActiveBusBackedPlugin() throws {
        let docs = try [
            repoFile("FEATURES.md"),
            repoFile("Merlin/Docs/UserGuide.md"),
            repoFile("Merlin/Docs/DeveloperManual.md"),
        ].joined(separator: "\n")

        XCTAssertTrue(docs.contains("plugins/electronics"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("workspace bus"))
        XCTAssertFalse(docs.localizedCaseInsensitiveContains("powered by an external MCP server"))
        XCTAssertFalse(docs.localizedCaseInsensitiveContains("execution is delegated to `merlin-kicad-mcp`"))
    }

    func testElectronicsDocsDescribeCompletionBackendArtifactsGatesAndPanel() throws {
        let docs = try [
            repoFile("FEATURES.md"),
            repoFile("Merlin/Docs/UserGuide.md"),
            repoFile("Merlin/Docs/DeveloperManual.md"),
        ].joined(separator: "\n")

        XCTAssertTrue(docs.localizedCaseInsensitiveContains("local FreeRouting"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("hosted FreeRouting"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("Gerbers"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("Excellon"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("pick-and-place"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("verification report"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("electronics job"))
        XCTAssertTrue(docs.localizedCaseInsensitiveContains("blocked"))
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
