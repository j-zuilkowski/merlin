import Foundation
import CoreServices
import SwiftUI

enum MessageDensity: String, CaseIterable, Codable, Sendable {
    case compact
    case comfortable
    case spacious
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var autoCompact: Bool = false
    @Published var maxTokens: Int = 8_192
    @Published var keepAwake: Bool = false
    @Published var providerName: String = "anthropic"
    @Published var modelID: String = ""
    @Published var defaultPermissionMode: PermissionMode = .ask
    @Published var notificationsEnabled: Bool = true
    @Published var messageDensity: MessageDensity = .comfortable
    @Published var standingInstructions: String = ""
    @Published var hooks: [HookConfig] = []
    @Published var appearance: AppearanceSettings = AppearanceSettings()
    @Published var providers: [ProviderConfig] = ProviderRegistry.defaultProviders
    @Published var reasoningEnabledOverrides: [String: Bool] = [:]
    @Published var maxSubagentThreads: Int = 4
    @Published var maxSubagentDepth: Int = 2
    @Published var disabledSkillNames: [String] = []
    @Published var memoriesEnabled: Bool = false
    @Published var memoryIdleTimeout: TimeInterval = 300
    @Published var xcalibreToken: String = ""

    var proposalApprover: ((SettingsProposal) async -> Bool)?

    private var fsStream: FSEventStreamRef?
    private var watchedURL: URL?

    private struct ConfigFile: Codable, Sendable {
        var autoCompact: Bool?
        var maxTokens: Int?
        var keepAwake: Bool?
        var providerName: String?
        var modelID: String?
        var defaultPermissionMode: PermissionMode?
        var notificationsEnabled: Bool?
        var messageDensity: MessageDensity?
        var standingInstructions: String?
        var hooks: [HookConfig]?
        var appearance: AppearanceSettings?
        var providers: [ProviderConfig]?
        var reasoningEnabledOverrides: [String: Bool]?
        var maxSubagentThreads: Int?
        var maxSubagentDepth: Int?
        var disabledSkillNames: [String]?
        var memoriesEnabled: Bool?
        var memoryIdleTimeout: TimeInterval?
        var xcalibreToken: String?

        enum CodingKeys: String, CodingKey {
            case autoCompact = "auto_compact"
            case maxTokens = "max_tokens"
            case keepAwake = "keep_awake"
            case providerName = "provider_name"
            case modelID = "model_id"
            case defaultPermissionMode = "default_permission_mode"
            case notificationsEnabled = "notifications_enabled"
            case messageDensity = "message_density"
            case standingInstructions = "standing_instructions"
            case hooks
            case appearance
            case providers
            case reasoningEnabledOverrides = "model_capabilities"
            case maxSubagentThreads = "max_subagent_threads"
            case maxSubagentDepth = "max_subagent_depth"
            case disabledSkillNames = "disabled_skill_names"
            case memoriesEnabled = "memories_enabled"
            case memoryIdleTimeout = "memory_idle_timeout"
            case xcalibreToken = "xcalibre_token"
        }
    }

    func load(from url: URL) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        let source = try String(contentsOf: url, encoding: .utf8)
        let decoder = TOMLDecoder()
        let config = try decoder.decode(ConfigFile.self, from: source)

        if let value = config.autoCompact {
            autoCompact = value
        }
        if let value = config.maxTokens {
            maxTokens = value
        }
        if let value = config.keepAwake {
            keepAwake = value
        }
        if let value = config.providerName {
            providerName = value
        }
        if let value = config.modelID {
            modelID = value
        }
        if let value = config.defaultPermissionMode {
            defaultPermissionMode = value
        }
        if let value = config.notificationsEnabled {
            notificationsEnabled = value
        }
        if let value = config.messageDensity {
            messageDensity = value
        }
        if let value = config.standingInstructions {
            standingInstructions = value
        }
        if let value = config.hooks {
            hooks = value
        }
        if let value = config.appearance {
            appearance = value
        }
        if let value = config.providers {
            providers = value
        }
        if let value = config.reasoningEnabledOverrides {
            reasoningEnabledOverrides = value
        }
        if let value = config.maxSubagentThreads {
            maxSubagentThreads = value
        }
        if let value = config.maxSubagentDepth {
            maxSubagentDepth = value
        }
        if let value = config.disabledSkillNames {
            disabledSkillNames = value
        }
        if let value = config.memoriesEnabled {
            memoriesEnabled = value
        }
        if let value = config.memoryIdleTimeout {
            memoryIdleTimeout = value
        }
        if let value = config.xcalibreToken {
            xcalibreToken = value
        }
    }

    func save(to url: URL) async throws {
        var lines: [String] = []
        lines.append("auto_compact = \(autoCompact)")
        lines.append("max_tokens = \(maxTokens)")
        lines.append("keep_awake = \(keepAwake)")
        lines.append("provider_name = \(quoted(providerName))")
        lines.append("model_id = \(quoted(modelID))")
        lines.append("default_permission_mode = \(quoted(defaultPermissionMode.rawValue))")
        lines.append("notifications_enabled = \(notificationsEnabled)")
        lines.append("message_density = \(quoted(messageDensity.rawValue))")
        lines.append("max_subagent_threads = \(maxSubagentThreads)")
        lines.append("max_subagent_depth = \(maxSubagentDepth)")
        if !xcalibreToken.isEmpty {
            lines.append("xcalibre_token = \(quoted(xcalibreToken))")
        }
        if disabledSkillNames.isEmpty == false {
            let quoted = disabledSkillNames.map { "\"\($0)\"" }.joined(separator: ", ")
            lines.append("disabled_skill_names = [\(quoted)]")
        }
        if memoriesEnabled {
            lines.append("memories_enabled = true")
            lines.append("memory_idle_timeout = \(memoryIdleTimeout)")
        }
        if standingInstructions.isEmpty == false {
            lines.append("standing_instructions = \(quoted(standingInstructions))")
        }

        lines.append("")
        lines.append("[appearance]")
        lines.append("theme = \(quoted(appearance.theme.rawValue))")
        lines.append("font_size = \(appearance.fontSize)")
        lines.append("font_name = \(quoted(appearance.fontName))")
        if appearance.accentColorHex.isEmpty == false {
            lines.append("accent_color_hex = \(quoted(appearance.accentColorHex))")
        }
        lines.append("line_spacing = \(appearance.lineSpacing)")

        if providers.isEmpty == false {
            lines.append("")
            for provider in providers {
                lines.append("[[providers]]")
                lines.append("id = \(quoted(provider.id))")
                lines.append("displayName = \(quoted(provider.displayName))")
                lines.append("baseURL = \(quoted(provider.baseURL))")
                lines.append("model = \(quoted(provider.model))")
                lines.append("isEnabled = \(provider.isEnabled)")
                lines.append("isLocal = \(provider.isLocal)")
                lines.append("supportsThinking = \(provider.supportsThinking)")
                lines.append("supportsVision = \(provider.supportsVision)")
                lines.append("kind = \(quoted(provider.kind.rawValue))")
                lines.append("")
            }
            if lines.last?.isEmpty == true {
                lines.removeLast()
            }
        }

        if reasoningEnabledOverrides.isEmpty == false {
            lines.append("")
            lines.append("[model_capabilities]")
            for key in reasoningEnabledOverrides.keys.sorted() {
                if let value = reasoningEnabledOverrides[key] {
                    lines.append("\(quoted(key)) = \(value)")
                }
            }
        }

        if hooks.isEmpty == false {
            lines.append("")
            for hook in hooks {
                lines.append("[[hooks]]")
                lines.append("event = \(quoted(hook.event))")
                lines.append("command = \(quoted(hook.command))")
                lines.append("enabled = \(hook.enabled)")
                lines.append("")
            }
            if lines.last?.isEmpty == true {
                lines.removeLast()
            }
        }

        let content = lines.joined(separator: "\n") + "\n"
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func propose(_ change: SettingsProposal) async -> Bool {
        guard let proposalApprover else {
            return false
        }

        let approved = await proposalApprover(change)
        if approved {
            apply(change)
        }
        return approved
    }

    func startWatching(url: URL) {
        stopWatching()
        watchedURL = url

        let directory = url.deletingLastPathComponent().path as CFString
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else {
                return
            }
            let settings = Unmanaged<AppSettings>.fromOpaque(info).takeUnretainedValue()
            Task { @MainActor in
                guard let watchedURL = settings.watchedURL else {
                    return
                }
                try? await settings.load(from: watchedURL)
            }
        }

        fsStream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            [directory] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents)
        )

        if let stream = fsStream {
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
            FSEventStreamStart(stream)
        }
    }

    func stopWatching() {
        guard let stream = fsStream else {
            return
        }
        FSEventStreamSetDispatchQueue(stream, nil)
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        fsStream = nil
    }

    private func apply(_ change: SettingsProposal) {
        switch change {
        case .setMaxTokens(let value):
            maxTokens = value
        case .setProviderName(let value):
            providerName = value
        case .setModelID(let value):
            modelID = value
        case .setAutoCompact(let value):
            autoCompact = value
        case .setStandingInstructions(let value):
            standingInstructions = value
        case .addHook(let value):
            hooks.append(value)
        case .removeHook(let event):
            hooks.removeAll { $0.event == event }
        }
    }

    private func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }
}
