import Foundation

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
