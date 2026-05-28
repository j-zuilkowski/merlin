import Foundation

struct DomainActivationSuggestion: Equatable, Sendable {
    var domainID: String
    var displayName: String
    var reason: String
}

/// The built-in software development domain. Always registered; cannot be removed.
/// Covers Swift/Xcode natively and any language/platform via SSH or MCP plugins.
struct SoftwareDomain: DomainPlugin {

    static let defaultID = "software"
    static let defaultActiveDomainIDs = [defaultID]

    let id = Self.defaultID
    let displayName = "Software Development"
    let highStakesKeywords = [
        "authentication", "auth", "security", "migration", "schema migration",
        "database schema", "permissions", "encryption", "secret", "token",
        "payment", "billing", "production deploy", "force push"
    ]
    let systemPromptAddendum: String? = nil
    let mcpToolNames: [String] = []

    let taskTypes: [DomainTaskType] = [
        DomainTaskType(domainID: Self.defaultID, name: "code_generation",   displayName: "Code Generation"),
        DomainTaskType(domainID: Self.defaultID, name: "refactoring",        displayName: "Refactoring"),
        DomainTaskType(domainID: Self.defaultID, name: "test_writing",       displayName: "Test Writing"),
        DomainTaskType(domainID: Self.defaultID, name: "explanation",        displayName: "Explanation"),
        DomainTaskType(domainID: Self.defaultID, name: "debugging",          displayName: "Debugging"),
        DomainTaskType(domainID: Self.defaultID, name: "schema_migration",   displayName: "Schema Migration"),
        DomainTaskType(domainID: Self.defaultID, name: "security_logic",     displayName: "Security Logic"),
    ]

    var verificationBackend: any VerificationBackend {
        SoftwareVerificationBackend()
    }

    var capabilities: [WorkspaceCapability] {
        [
            WorkspaceCapability(
                id: "domain.software.verify",
                displayName: "Software Verification",
                kind: .verification,
                address: WorkspaceMessageAddress(namespace: "domain.software", capability: "verify"),
                requiredPermissionScope: .externalSideEffect
            )
        ]
    }
}

struct ElectronicsDomain: DomainPlugin {
    static let defaultID = "electronics"

    let id = Self.defaultID
    let displayName = "Electronics"
    let highStakesKeywords = [
        "mains", "high voltage", "isolation", "creepage", "clearance",
        "board house", "fabrication", "gerber", "bom", "pcb", "schematic",
        "footprint", "autoroute", "spice", "vendor order", "place order"
    ]
    let systemPromptAddendum: String? = """
    Active domain: Electronics. Use the verified KiCad/electronics MCP or workspace \
    plugin tool path when it is available. For end-to-end requirements-to-PCB board \
    design tasks, your first tool call must be `workflow.requirements_to_pcb` with \
    the user's board requirements. After that workflow returns, inspect or verify \
    the returned artifacts using `kicad_*` tools as needed. Do not create a \
    requirements file yourself, and do not call `kicad_build_intent_model` with a \
    path unless a previous electronics tool returned that exact artifact path. \
    Treat netlists, schematics, PCB files, BOMs, and fabrication outputs as domain \
    artifacts that should be produced and verified through the electronics \
    toolchain rather than hand-written freeform text. Manufacturing, ordering, and \
    other irreversible electronics actions require explicit user approval.
    """
    let mcpToolNames: [String] = []

    let taskTypes: [DomainTaskType] = [
        DomainTaskType(domainID: Self.defaultID, name: "schematic_design", displayName: "Schematic Design"),
        DomainTaskType(domainID: Self.defaultID, name: "pcb_layout", displayName: "PCB Layout"),
        DomainTaskType(domainID: Self.defaultID, name: "component_selection", displayName: "Component Selection"),
        DomainTaskType(domainID: Self.defaultID, name: "simulation", displayName: "Simulation"),
        DomainTaskType(domainID: Self.defaultID, name: "verification", displayName: "Verification"),
        DomainTaskType(domainID: Self.defaultID, name: "manufacturing_release", displayName: "Manufacturing Release"),
    ]

    var verificationBackend: any VerificationBackend {
        NullVerificationBackend()
    }

    var capabilities: [WorkspaceCapability] {
        [
            WorkspaceCapability(
                id: "domain.electronics.verify",
                displayName: "Electronics Verification",
                kind: .verification,
                address: WorkspaceMessageAddress(namespace: "domain.electronics", capability: "verify"),
                requiredPermissionScope: .externalSideEffect
            )
        ] + KiCadToolDefinitions.requiredToolNames.map { toolName in
            WorkspaceCapability(
                id: "domain.electronics.\(toolName)",
                displayName: toolName,
                kind: .tool,
                address: WorkspaceMessageAddress(namespace: "domain.electronics", capability: toolName),
                requiredPermissionScope: toolName == "kicad_submit_vendor_order" ? .userApprovedIrreversible : .externalSideEffect
            )
        }
    }

    var settingsSchema: WorkspaceSettingsSchema? {
        WorkspaceSettingsSchema(
            namespace: "domain.electronics",
            title: "Electronics",
            fields: [
                WorkspaceSettingsField(
                    key: "kicad_cli_path",
                    label: "KiCad CLI Path",
                    kind: .path,
                    defaultValue: nil,
                    isSecret: false,
                    help: "Path to kicad-cli."
                )
            ]
        )
    }

    static func suggestedActivation(
        for message: String,
        currentActiveDomainIDs: [String]
    ) -> DomainActivationSuggestion? {
        guard currentActiveDomainIDs.contains(defaultID) == false else {
            return nil
        }

        let normalized = normalizedActivationText(message)
        for phrase in explicitTriggerPhrases {
            if normalized.contains(phrase) {
                return DomainActivationSuggestion(
                    domainID: defaultID,
                    displayName: ElectronicsDomain().displayName,
                    reason: "Detected electronics intent from '\(phrase.trimmingCharacters(in: .whitespaces))'."
                )
            }
        }

        if containsAnyWord(in: normalized, words: boardWords),
           containsAnyWord(in: normalized, words: boardContextWords) {
            return DomainActivationSuggestion(
                domainID: defaultID,
                displayName: ElectronicsDomain().displayName,
                reason: "Detected PCB/board design intent in the current prompt."
            )
        }

        if containsAnyWord(in: normalized, words: circuitWords),
           containsAnyWord(in: normalized, words: circuitContextWords) {
            return DomainActivationSuggestion(
                domainID: defaultID,
                displayName: ElectronicsDomain().displayName,
                reason: "Detected circuit/schematic design intent in the current prompt."
            )
        }

        return nil
    }

    static func projectLooksLikeElectronics(_ path: String) -> Bool {
        let rootURL = URL(fileURLWithPath: path)
        let fm = FileManager.default
        guard fm.fileExists(atPath: rootURL.path) else { return false }

        if let entries = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil) {
            if entries.contains(where: { $0.pathExtension == "kicad_pro" }) {
                return true
            }
        }

        guard let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return false
        }

        var scanned = 0
        for case let url as URL in enumerator {
            scanned += 1
            if url.pathExtension == "kicad_pro" {
                return true
            }
            if scanned >= 1_000 {
                break
            }
        }
        return false
    }

    private static let explicitTriggerPhrases: [String] = [
        " kicad ",
        " .kicad_pro ",
        " .kicad_sch ",
        " .kicad_pcb ",
        " pcb ",
        " schematic ",
        " gerber ",
        " netlist ",
        " footprint ",
        " footprints ",
        " bom ",
        " spice simulation ",
        " board house ",
        " pick and place ",
    ]

    private static let boardWords: [String] = [
        "board", "pcb", "gerber", "bom", "netlist", "footprint", "footprints"
    ]

    private static let boardContextWords: [String] = [
        "layout", "route", "routing", "fabrication", "manufacturing",
        "place", "placement", "autoroute", "trace", "traces", "stackup"
    ]

    private static let circuitWords: [String] = [
        "circuit", "schematic", "electronics", "electronic"
    ]

    private static let circuitContextWords: [String] = [
        "design", "draw", "capture", "erc", "drc", "spice", "simulate", "simulation"
    ]

    private static func containsAnyWord(in normalizedMessage: String, words: [String]) -> Bool {
        words.contains { normalizedMessage.contains(" \($0) ") }
    }

    private static func normalizedActivationText(_ message: String) -> String {
        let scalars = message.lowercased().unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" {
                return Character(scalar)
            }
            return " "
        }
        let collapsed = String(scalars)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return " \(collapsed) "
    }
}

/// Software verification backend — runs compile, test, lint via ShellTool.
/// Commands are read from AppSettings (verifyCommand, checkCommand) at call time.
@MainActor
struct SoftwareVerificationBackend: VerificationBackend {

    func verificationCommands(for taskType: DomainTaskType) async -> [VerificationCommand]? {
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
            return nil
        }
    }
}
