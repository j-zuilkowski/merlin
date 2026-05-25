# Phase 99b — DomainRegistry + DomainPlugin + MCPDomainAdapter + SoftwareDomain

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
Phase 99a complete: failing tests in place.

---

## Write to: Merlin/MCP/DomainPlugin.swift

```swift
import Foundation

// MARK: - DomainTaskType

/// A domain-registered task classification. Not a hardcoded enum — domains
/// contribute their own task types at registration time.
struct DomainTaskType: Hashable, Codable, Sendable {
    var domainID: String   // e.g. "software", "pcb", "construction"
    var name: String       // e.g. "code_generation", "schematic"
    var displayName: String
}

// MARK: - DomainPlugin

/// Adopted by built-in domains (SoftwareDomain) and by MCPDomainAdapter
/// when wrapping an external MCP domain server.
protocol DomainPlugin: Sendable {
    var id: String { get }
    var displayName: String { get }
    var taskTypes: [DomainTaskType] { get }
    var verificationBackend: any VerificationBackend { get }
    var highStakesKeywords: [String] { get }
    /// Appended to the provider's system prompt addendum (if any). nil = nothing added.
    var systemPromptAddendum: String? { get }
    /// MCP tool names contributed by this domain (used by ToolRegistry at domain activation).
    var mcpToolNames: [String] { get }
}

// MARK: - DomainManifest (MCP wire format)

/// JSON shape served at `merlin://domain/manifest` by an MCP domain server.
struct DomainManifest: Decodable, Sendable {
    var id: String
    var displayName: String
    var taskTypes: [DomainTaskType]
    var highStakesKeywords: [String]
    var systemPromptAddendum: String?
    /// Key = task type name, value = list of verification commands for that type.
    var verificationCommands: [String: [ManifestVerificationCommand]]

    struct ManifestVerificationCommand: Decodable, Sendable {
        var label: String
        var command: String
        var passCondition: ManifestPassCondition

        enum ManifestPassCondition: Decodable, Sendable {
            case exitCode(Int)
            case outputContains(String)

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type_ = try container.decode(String.self, forKey: .type)
                switch type_ {
                case "exitCode":
                    self = .exitCode(try container.decode(Int.self, forKey: .value))
                case "outputContains":
                    self = .outputContains(try container.decode(String.self, forKey: .value))
                default:
                    self = .exitCode(0)
                }
            }

            enum CodingKeys: String, CodingKey { case type, value }
        }
    }
}

// MARK: - MCPDomainAdapter

/// Bridges an external MCP domain server (which cannot adopt Swift protocols)
/// into the DomainPlugin protocol by reading its DomainManifest resource.
struct MCPDomainAdapter: DomainPlugin {
    let id: String
    let displayName: String
    let taskTypes: [DomainTaskType]
    let highStakesKeywords: [String]
    let systemPromptAddendum: String?
    let mcpToolNames: [String]
    let verificationBackend: any VerificationBackend

    init(manifest: DomainManifest, mcpServerID: String) {
        self.id = manifest.id
        self.displayName = manifest.displayName
        self.taskTypes = manifest.taskTypes
        self.highStakesKeywords = manifest.highStakesKeywords
        self.systemPromptAddendum = manifest.systemPromptAddendum
        self.mcpToolNames = []  // populated from MCPBridge tool list at connection time
        self.verificationBackend = ManifestVerificationBackend(
            commands: manifest.verificationCommands
        )
    }
}

// MARK: - ManifestVerificationBackend

/// VerificationBackend built from a DomainManifest's verificationCommands map.
struct ManifestVerificationBackend: VerificationBackend {
    private let commandMap: [String: [DomainManifest.ManifestVerificationCommand]]

    init(commands: [String: [DomainManifest.ManifestVerificationCommand]]) {
        self.commandMap = commands
    }

    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]? {
        guard let cmds = commandMap[taskType.name], !cmds.isEmpty else { return nil }
        return cmds.map { c in
            let condition: PassCondition
            switch c.passCondition {
            case .exitCode(let code): condition = .exitCode(code)
            case .outputContains(let s): condition = .outputContains(s)
            }
            return VerificationCommand(label: c.label, command: c.command, passCondition: condition)
        }
    }
}
```

---

## Write to: Merlin/Engine/VerificationBackend.swift

```swift
import Foundation

// MARK: - PassCondition

enum PassCondition: Sendable {
    case exitCode(Int)
    case outputContains(String)
    case custom(@Sendable (String) -> Bool)
}

// MARK: - VerificationCommand

struct VerificationCommand: Sendable {
    var label: String
    var command: String
    var passCondition: PassCondition
}

// MARK: - VerificationBackend

/// Stage 1 critic: domain-provided deterministic verification.
/// The backend is initialised with its config at construction — no config param per call.
protocol VerificationBackend: Sendable {
    /// Returns nil if this domain has no deterministic check for the given task type.
    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]?
}

// MARK: - NullVerificationBackend

/// Used when a domain has no deterministic verification.
/// Stage 1 always passes; Stage 2 (model critic) handles all verification.
struct NullVerificationBackend: VerificationBackend {
    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]? { nil }
}
```

---

## Write to: Merlin/MCP/DomainRegistry.swift

```swift
import Foundation

/// Runtime registry of domain plugins. One active domain at a time.
/// Multi-domain sessions are deferred.
actor DomainRegistry {

    static let shared = DomainRegistry()

    private var plugins: [String: any DomainPlugin] = [:]
    private var activeDomainID: String = "software"

    init() {
        // SoftwareDomain is always registered and cannot be removed.
        let software = SoftwareDomain()
        plugins[software.id] = software
    }

    func register(_ plugin: any DomainPlugin) {
        plugins[plugin.id] = plugin
    }

    func unregister(id: String) {
        guard id != "software" else { return }  // SoftwareDomain is permanent
        plugins.removeValue(forKey: id)
        if activeDomainID == id {
            activeDomainID = "software"
        }
    }

    func setActiveDomain(id: String) {
        guard plugins[id] != nil else { return }
        activeDomainID = id
    }

    func activeDomain() -> any DomainPlugin {
        plugins[activeDomainID] ?? plugins["software"]!
    }

    /// Returns task types for the active domain only. Multi-domain is deferred.
    func taskTypes() -> [DomainTaskType] {
        activeDomain().taskTypes
    }

    func plugin(for id: String) -> (any DomainPlugin)? {
        plugins[id]
    }
}
```

---

## Write to: Merlin/MCP/SoftwareDomain.swift

```swift
import Foundation

/// The built-in software development domain. Always registered; cannot be removed.
/// Covers Swift/Xcode natively and any language/platform via SSH or MCP plugins.
struct SoftwareDomain: DomainPlugin {

    let id = "software"
    let displayName = "Software Development"
    let highStakesKeywords = [
        "authentication", "auth", "security", "migration", "schema migration",
        "database schema", "permissions", "encryption", "secret", "token",
        "payment", "billing", "production deploy", "force push"
    ]
    let systemPromptAddendum: String? = nil
    let mcpToolNames: [String] = []

    let taskTypes: [DomainTaskType] = [
        DomainTaskType(domainID: "software", name: "code_generation",   displayName: "Code Generation"),
        DomainTaskType(domainID: "software", name: "refactoring",       displayName: "Refactoring"),
        DomainTaskType(domainID: "software", name: "test_writing",      displayName: "Test Writing"),
        DomainTaskType(domainID: "software", name: "explanation",       displayName: "Explanation"),
        DomainTaskType(domainID: "software", name: "debugging",         displayName: "Debugging"),
        DomainTaskType(domainID: "software", name: "schema_migration",  displayName: "Schema Migration"),
        DomainTaskType(domainID: "software", name: "security_logic",    displayName: "Security Logic"),
    ]

    var verificationBackend: any VerificationBackend {
        SoftwareVerificationBackend()
    }
}

/// Software verification backend — runs compile, test, lint via ShellTool.
/// Commands are read from AppSettings (verify_command, check_command) at call time.
struct SoftwareVerificationBackend: VerificationBackend {

    func verificationCommands(for taskType: DomainTaskType) -> [VerificationCommand]? {
        let settings = AppSettings.shared
        switch taskType.name {
        case "code_generation", "refactoring", "test_writing", "debugging",
             "schema_migration", "security_logic":
            var commands: [VerificationCommand] = []
            if !settings.verifyCommand.isEmpty {
                commands.append(VerificationCommand(
                    label: "Build / Compile",
                    command: settings.verifyCommand,
                    passCondition: .exitCode(0)
                ))
            }
            if !settings.checkCommand.isEmpty {
                commands.append(VerificationCommand(
                    label: "Lint / Check",
                    command: settings.checkCommand,
                    passCondition: .exitCode(0)
                ))
            }
            return commands.isEmpty ? nil : commands
        default:
            return nil  // explanations, summaries — no deterministic check
        }
    }
}
```

---

## AppSettings additions (add to Merlin/Config/AppSettings.swift)

Add these properties to `AppSettings`:
```swift
// MARK: - V5 Domain + Role Slots (config.toml keys)

/// Shell command used by SoftwareVerificationBackend to compile/build.
/// Example: "xcodebuild -scheme MyApp build" or "cargo check"
@Published var verifyCommand: String = ""

/// Shell command used by SoftwareVerificationBackend to lint/check.
/// Example: "cargo clippy -- -D warnings" or "swiftlint"
@Published var checkCommand: String = ""

/// Active domain plugin ID. "software" by default.
@Published var activeDomainID: String = "software"
```

Load in `load(from:)` under `[domain]` TOML key:
```swift
if let domain = toml["domain"] as? [String: Any] {
    verifyCommand  = domain["verify_command"] as? String ?? ""
    checkCommand   = domain["check_command"]  as? String ?? ""
    activeDomainID = domain["active_domain"]  as? String ?? "software"
}
```

config.toml schema addition:
```toml
[domain]
active_domain  = "software"   # domain plugin ID
verify_command = ""           # e.g. "xcodebuild -scheme Merlin build" or "cargo check"
check_command  = ""           # e.g. "cargo clippy -- -D warnings"
```

---

## project.yml additions

Add new source files to the `Merlin` target sources:
```yaml
- Merlin/MCP/DomainPlugin.swift
- Merlin/MCP/DomainRegistry.swift
- Merlin/MCP/SoftwareDomain.swift
- Merlin/Engine/VerificationBackend.swift
```

Then regenerate:
```bash
cd ~/Documents/localProject/merlin
xcodegen generate
```

---

## Verify
```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests test \
    -destination 'platform=macOS' \
    -derivedDataPath /tmp/merlin-derived 2>&1 \
    | grep -E 'DomainRegistry.*passed|DomainRegistry.*failed|DomainManifest.*passed|DomainManifest.*failed|BUILD SUCCEEDED|BUILD FAILED' | head -40
```
Expected: BUILD SUCCEEDED; DomainRegistryTests → 5 pass; DomainManifestTests → 2 pass.

## Commit
```bash
cd ~/Documents/localProject/merlin
git add Merlin/MCP/DomainPlugin.swift \
        Merlin/MCP/DomainRegistry.swift \
        Merlin/MCP/SoftwareDomain.swift \
        Merlin/Engine/VerificationBackend.swift \
        Merlin/Config/AppSettings.swift \
        project.yml
git commit -m "Phase 99b — DomainRegistry + DomainPlugin + MCPDomainAdapter + SoftwareDomain"
```
