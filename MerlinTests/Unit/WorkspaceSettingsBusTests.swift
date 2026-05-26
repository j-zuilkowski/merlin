import XCTest
@testable import Merlin

@MainActor
final class WorkspaceSettingsBusTests: XCTestCase {
    func testSettingsSchemaRegistersAndPersistsWorkspaceValues() async throws {
        let runtime = try makeRuntime()
        let schema = WorkspaceSettingsSchema(
            namespace: "plugin.demo",
            title: "Demo",
            fields: [
                WorkspaceSettingsField(key: "enabled", label: "Enabled", kind: .boolean, defaultValue: .boolean(false), isSecret: false, help: nil),
                WorkspaceSettingsField(key: "token", label: "Token", kind: .secret, defaultValue: nil, isSecret: true, help: nil),
            ]
        )

        await runtime.bus.registerSettingsSchema(schema)
        try await runtime.settingsStore.save(
            WorkspaceSettingsNamespace(namespace: "plugin.demo", values: [
                "enabled": .boolean(true),
                "token": .string("do-not-store"),
            ])
        )

        let loaded = try runtime.settingsStore.load(namespace: "plugin.demo")
        XCTAssertEqual(loaded.values["enabled"], .boolean(true))
        XCTAssertNil(loaded.values["token"])
        let text = try String(contentsOf: runtime.settingsURL(namespace: "plugin.demo"), encoding: .utf8)
        XCTAssertFalse(text.contains("do-not-store"))
    }

    func testSavingSettingsPublishesChangedEvent() async throws {
        let runtime = try makeRuntime()
        try await runtime.settingsStore.save(WorkspaceSettingsNamespace(namespace: "plugin.demo", values: ["enabled": .boolean(true)]))

        let events = await runtime.bus.recentEvents(matching: WorkspaceMessageEventFilter(namespacePrefix: "plugin.demo"))
        XCTAssertTrue(events.contains { $0.kind == .settingsChanged })
    }

    private func makeRuntime() throws -> WorkspaceRuntime {
        try WorkspaceRuntime(
            rootURL: URL(fileURLWithPath: "/tmp"),
            merlinHomeURL: FileManager.default.temporaryDirectory.appendingPathComponent("merlin-settings-tests-\(UUID().uuidString)")
        )
    }
}
