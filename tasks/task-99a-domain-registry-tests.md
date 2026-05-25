# Phase 99a — DomainRegistry Tests (failing)

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin

Phase 98 complete: V4 fully shipped. Starting V5 — Domain Plugin System + Supervisor-Worker architecture.

New surface introduced in phase 99b:
  - `DomainTaskType` — domain-registered task type (domainID + name)
  - `DomainPlugin` protocol — adopted by built-in domains and MCPDomainAdapter
  - `DomainManifest` — Decodable JSON shape served by MCP domain servers
  - `MCPDomainAdapter` — wraps a DomainManifest into a DomainPlugin
  - `DomainRegistry.shared` — actor; register/unregister/activeDomain/taskTypes
  - `SoftwareDomain` — always-registered built-in; cannot be removed
  - `NullVerificationBackend` — placeholder until VerificationBackend phase

TDD coverage:
  File 1 — DomainRegistryTests: registration, unregistration, active domain fallback, taskTypes returns active domain only
  File 2 — DomainManifestTests: JSON decoding of a DomainManifest into MCPDomainAdapter

---

## Write to: MerlinTests/Unit/DomainRegistryTests.swift

```swift
import XCTest
@testable import Merlin

final class DomainRegistryTests: XCTestCase {

    // Each test gets an isolated registry to avoid cross-test state.
    // DomainRegistry.shared is the singleton used at runtime; tests
    // use a fresh local instance via a dedicated init.

    func testActiveDomainDefaultsToSoftwareDomain() async {
        let registry = DomainRegistry()
        let domain = await registry.activeDomain()
        XCTAssertEqual(domain.id, "software")
    }

    func testRegisterAndActivateDomain() async {
        let registry = DomainRegistry()
        let pcb = StubDomain(id: "pcb", displayName: "PCB Design")
        await registry.register(pcb)
        await registry.setActiveDomain(id: "pcb")
        let domain = await registry.activeDomain()
        XCTAssertEqual(domain.id, "pcb")
    }

    func testUnregisterDomainFallsBackToSoftware() async {
        let registry = DomainRegistry()
        let pcb = StubDomain(id: "pcb", displayName: "PCB Design")
        await registry.register(pcb)
        await registry.setActiveDomain(id: "pcb")
        await registry.unregister(id: "pcb")
        let domain = await registry.activeDomain()
        XCTAssertEqual(domain.id, "software")
    }

    func testSoftwareDomainCannotBeUnregistered() async {
        let registry = DomainRegistry()
        await registry.unregister(id: "software")  // should be a no-op
        let domain = await registry.activeDomain()
        XCTAssertEqual(domain.id, "software")
    }

    func testTaskTypesReturnsActiveDomainOnlyNotUnion() async {
        let registry = DomainRegistry()
        let pcb = StubDomain(id: "pcb", displayName: "PCB Design",
                             taskTypes: [DomainTaskType(domainID: "pcb", name: "schematic", displayName: "Schematic")])
        await registry.register(pcb)

        // While software is active, only software task types returned
        let softwareTypes = await registry.taskTypes()
        XCTAssertTrue(softwareTypes.allSatisfy { $0.domainID == "software" })

        await registry.setActiveDomain(id: "pcb")
        let pcbTypes = await registry.taskTypes()
        XCTAssertTrue(pcbTypes.allSatisfy { $0.domainID == "pcb" })
        XCTAssertFalse(pcbTypes.contains(where: { $0.domainID == "software" }))
    }

    func testPluginLookup() async {
        let registry = DomainRegistry()
        let pcb = StubDomain(id: "pcb", displayName: "PCB Design")
        await registry.register(pcb)
        let found = await registry.plugin(for: "pcb")
        XCTAssertEqual(found?.id, "pcb")
        let missing = await registry.plugin(for: "nonexistent")
        XCTAssertNil(missing)
    }
}

final class DomainManifestTests: XCTestCase {

    func testDecodesManifestFromJSON() throws {
        let json = """
        {
            "id": "pcb",
            "displayName": "PCB Design",
            "taskTypes": [
                { "domainID": "pcb", "name": "schematic", "displayName": "Schematic Design" }
            ],
            "highStakesKeywords": ["power routing", "impedance"],
            "systemPromptAddendum": "Always follow IPC-2221 spacing rules.",
            "verificationCommands": {}
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(DomainManifest.self, from: json)
        XCTAssertEqual(manifest.id, "pcb")
        XCTAssertEqual(manifest.taskTypes.count, 1)
        XCTAssertEqual(manifest.taskTypes[0].name, "schematic")
        XCTAssertEqual(manifest.highStakesKeywords, ["power routing", "impedance"])
        XCTAssertEqual(manifest.systemPromptAddendum, "Always follow IPC-2221 spacing rules.")
    }

    func testMCPDomainAdapterAdoptsDomainPlugin() throws {
        let json = """
        {
            "id": "pcb",
            "displayName": "PCB Design",
            "taskTypes": [],
            "highStakesKeywords": [],
            "verificationCommands": {}
        }
        """.data(using: .utf8)!
        let manifest = try JSONDecoder().decode(DomainManifest.self, from: json)
        let adapter = MCPDomainAdapter(manifest: manifest, mcpServerID: "pcb-server")
        XCTAssertEqual(adapter.id, "pcb")
        XCTAssertEqual(adapter.displayName, "PCB Design")
        XCTAssertNil(adapter.systemPromptAddendum)
    }
}

// MARK: - Test helpers

private struct StubDomain: DomainPlugin {
    var id: String
    var displayName: String
    var taskTypes: [DomainTaskType] = [
        DomainTaskType(domainID: "stub", name: "task", displayName: "Task")
    ]
    var verificationBackend: any VerificationBackend = NullVerificationBackend()
    var highStakesKeywords: [String] = []
    var systemPromptAddendum: String? = nil
    var mcpToolNames: [String] = []
}
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'error:|warning:|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD FAILED — `DomainRegistry`, `DomainPlugin`, `DomainTaskType`, `DomainManifest`, `MCPDomainAdapter`, `SoftwareDomain`, `NullVerificationBackend`, `VerificationBackend` not defined.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add MerlinTests/Unit/DomainRegistryTests.swift
git commit -m "Phase 99a — DomainRegistryTests + DomainManifestTests (failing)"
```
