import Foundation

struct SkillFrontmatter: Sendable {
    var name: String = ""
    var description: String = ""
    var argumentHint: String = ""
    var model: String = ""
    var userInvocable: Bool = true
    var disableModelInvocation: Bool = false
    var allowedTools: [String] = []
    var context: String = ""
    var role: AgentSlot?
    var complexity: ComplexityTier?

    static func parse(_ yaml: String) -> SkillFrontmatter {
        var frontmatter = SkillFrontmatter()

        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.split(separator: ":", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }

            let key = parts[0]
            let value = parts[1]
            switch key {
            case "name":
                frontmatter.name = value
            case "description":
                frontmatter.description = value
            case "argument-hint":
                frontmatter.argumentHint = value
            case "model":
                frontmatter.model = value
            case "user-invocable":
                frontmatter.userInvocable = value == "true"
            case "disable-model-invocation":
                frontmatter.disableModelInvocation = value == "true"
            case "context":
                frontmatter.context = value
            case "allowed-tools":
                frontmatter.allowedTools = value.components(separatedBy: " ").filter { !$0.isEmpty }
            case "role":
                frontmatter.role = AgentSlot(rawValue: value)
            case "complexity":
                frontmatter.complexity = ComplexityTier(rawValue: value)
            default:
                break
            }
        }

        return frontmatter
    }
}
