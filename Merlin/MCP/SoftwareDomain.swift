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
        DomainTaskType(domainID: "software", name: "refactoring",        displayName: "Refactoring"),
        DomainTaskType(domainID: "software", name: "test_writing",       displayName: "Test Writing"),
        DomainTaskType(domainID: "software", name: "explanation",        displayName: "Explanation"),
        DomainTaskType(domainID: "software", name: "debugging",          displayName: "Debugging"),
        DomainTaskType(domainID: "software", name: "schema_migration",   displayName: "Schema Migration"),
        DomainTaskType(domainID: "software", name: "security_logic",     displayName: "Security Logic"),
    ]

    var verificationBackend: any VerificationBackend {
        SoftwareVerificationBackend()
    }
}

/// Software verification backend — runs compile, test, lint via ShellTool.
/// Commands are read from AppSettings (verifyCommand, checkCommand) at call time.
@MainActor
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
            return nil
        }
    }
}
