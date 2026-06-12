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

    func testDeveloperManualMatchesCurrentEngineToolAndElectronicsSurfaces() throws {
        let manual = try repoFile("Merlin/Docs/DeveloperManual.md")

        for required in [
            "slotAssignments",
            "ProviderRegistry",
            "provider(for:)",
            "executable turn slot",
            "Merlin/Discipline/DisciplineEngine.swift",
            "Merlin/Runtime/",
            "Merlin/Electronics/",
            "Merlin/CAG/",
            "Merlin/Plugins/",
            "app_launch",
            "app_list_running",
            "ui_inspect",
            "ui_screenshot",
            "xcode_derived_data_clean",
            "xcode_simulator_boot",
            "tool_discover",
            "generate_dev_guide",
            "kicad_build_intent_model",
            "kicad_generate_circuit_ir",
            "kicad_select_components",
            "kicad_revise_component_selection",
            "kicad_compile_project",
            "kicad_generate_spice_scenario",
            "kicad_prepare_vendor_order",
            "kicad_package_release",
            "SCHEMATIC_VERIFIED",
            "PCB_VERIFIED",
            "BOM_READY",
            "FAB_READY",
            "COMPONENT_SELECTION_REVISION_BLOCKED",
        ] {
            XCTAssertTrue(manual.contains(required), "DeveloperManual.md missing current surface: \(required)")
        }

        for stale in [
            "proProvider",
            "flashProvider",
            "visionProvider",
            "proProvider.complete()",
            "Merlin/Engine/DisciplineEngine.swift",
            "xcode_open_simulator",
            "launch_app",
            "quit_app",
            "focus_app",
            "list_running_apps",
            "ax_inspect",
            "cg_event",
            "capture_screen",
            "kicad_create_project",
            "kicad_write_schematic",
            "kicad_set_board_constraints",
            "kicad_set_netclasses",
            "kicad_capture_schematic_png",
            "kicad_capture_pcb_png",
            "kicad_export_bom",
            "kicad_query_vendor",
            "kicad_run_cam_checks",
            "kicad_submit_order_approval",
            "kicad_release_approval",
        ] {
            XCTAssertFalse(manual.contains(stale), "DeveloperManual.md still contains stale surface: \(stale)")
        }
    }

    func testDeveloperManualCodeMapCoversSourceCommentCrossReferences() throws {
        let manual = try repoFile("Merlin/Docs/DeveloperManual.md")
        let sourceRoot = repoRootURL().appendingPathComponent("Merlin")
        let sourceFiles = try swiftFiles(in: sourceRoot)

        let references = try sourceFiles.flatMap { url -> [(path: String, section: String)] in
            let text = try String(contentsOf: url, encoding: .utf8)
            let path = url.path.replacingOccurrences(of: repoRootURL().path + "/Merlin/", with: "")
            return text
                .components(separatedBy: .newlines)
                .compactMap { line -> (path: String, section: String)? in
                    guard let section = developerManualSectionReference(in: line) else { return nil }
                    return (path, section)
                }
        }

        XCTAssertFalse(references.isEmpty, "Expected source comments to reference the Developer Manual")

        for reference in references {
            XCTAssertTrue(
                manual.contains("`\(reference.path)`"),
                "DeveloperManual.md Code Map missing source-commented file: \(reference.path)"
            )

            for heading in reference.section.components(separatedBy: "→").map({ $0.trimmingCharacters(in: .whitespaces) }) {
                XCTAssertTrue(
                    manual.contains("## \(heading)") || manual.contains("### \(heading)") || manual.contains("#### \(heading)"),
                    "DeveloperManual.md missing heading for source comment section: \(reference.section)"
                )
            }
        }
    }

    func testUserGuideTableOfContentsCoversCurrentUserFacingSections() throws {
        let guide = try repoFile("Merlin/Docs/UserGuide.md")
        let tableOfContents = try XCTUnwrap(
            guide.range(of: "## Table of Contents")
                .flatMap { start in
                    guide.range(of: "---", range: start.upperBound..<guide.endIndex)
                        .map { separator in String(guide[start.upperBound..<separator.lowerBound]) }
                }
        )

        for section in [
            "Electronics / KiCad Domain",
            "Behavioral Reliability",
            "Project Discipline",
            "Hooks",
            "Connectors",
            "Scheduled Automations",
            "LoRA Self-Training",
            "Settings",
            "Keyboard Shortcuts",
        ] {
            XCTAssertTrue(
                tableOfContents.contains(section),
                "UserGuide.md table of contents missing user-facing section: \(section)"
            )
        }
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

    private func swiftFiles(in root: URL) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )
        var files: [URL] = []
        guard let enumerator else { return files }
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: resourceKeys)
            if values.isRegularFile == true && url.pathExtension == "swift" {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func developerManualSectionReference(in line: String) -> String? {
        guard line.contains("Developer Manual §") else { return nil }
        if let firstQuote = line.firstIndex(of: "\""),
           let secondQuote = line[line.index(after: firstQuote)...].firstIndex(of: "\"") {
            return String(line[line.index(after: firstQuote)..<secondQuote])
        }

        guard let marker = line.range(of: "Developer Manual §") else { return nil }
        var section = line[marker.upperBound...].trimmingCharacters(in: .whitespaces)
        if section.hasSuffix(".") {
            section.removeLast()
        }
        return section.isEmpty ? nil : section
    }
}
