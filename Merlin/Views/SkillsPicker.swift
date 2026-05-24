import SwiftUI

struct SkillsPicker: View {
    @EnvironmentObject private var registry: SkillsRegistry
    @Binding var query: String
    let onSelect: (Skill) -> Void
    let onSelectBuiltin: (BuiltinSlashCommand) -> Void

    private var filteredSkills: [Skill] {
        let q = query.lowercased()
        return registry.skills.filter { skill in
            skill.frontmatter.userInvocable &&
            (q.isEmpty ||
             skill.name.lowercased().contains(q) ||
             skill.frontmatter.description.lowercased().contains(q))
        }
    }

    private var filteredBuiltins: [BuiltinSlashCommand] {
        BuiltinSlashCommands.matching(query: query)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Built-in slash commands section — surfaces /calibrate, /compact,
            // /rewind, /btw above user-loaded skills so they're discoverable
            // without consulting docs.
            if !filteredBuiltins.isEmpty {
                Text("Commands")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredBuiltins, id: \.name) { cmd in
                        Button {
                            onSelectBuiltin(cmd)
                        } label: {
                            HStack(spacing: 8) {
                                Text("/\(cmd.name)")
                                    .font(.caption.monospaced().weight(.medium))
                                    .foregroundStyle(.primary)
                                Text(cmd.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
            }

            Text("Skills")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            if filteredSkills.isEmpty {
                Text("No skills match")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(12)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(filteredSkills) { skill in
                            Button {
                                onSelect(skill)
                            } label: {
                                HStack(spacing: 8) {
                                    Text("/\(skill.name)")
                                        .font(.caption.monospaced().weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text(skill.frontmatter.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 5)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
        }
        .frame(width: 380)
    }
}
