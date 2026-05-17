import Foundation

/// The panes of the Settings window sidebar. Foundation-only (no SwiftUI) so it can be
/// compiled into the UI-testing target, which drives the real Settings window and needs
/// the canonical pane labels without `@testable import Merlin`.
enum SettingsSection: String, CaseIterable, Hashable {
    case general
    case appearance
    case providers
    case roleSlots
    case agents
    case hooks
    case scheduler
    case memories
    case library
    case mcp
    case skills
    case search
    case permissions
    case connectors
    case performance
    case lora
    case advanced

    var label: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .providers: return "Providers"
        case .roleSlots: return "Providers & Slots"
        case .agents: return "Agents"
        case .hooks: return "Hooks"
        case .scheduler: return "Scheduler"
        case .memories: return "Memories"
        case .library: return "Library"
        case .mcp: return "MCP Servers"
        case .skills: return "Skills"
        case .search: return "Web Search"
        case .permissions: return "Permissions"
        case .connectors: return "Connectors"
        case .performance: return "Performance Dashboard"
        case .lora: return "LoRA"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintbrush"
        case .providers: return "server.rack"
        case .roleSlots: return "person.3"
        case .agents: return "cpu"
        case .hooks: return "terminal"
        case .scheduler: return "clock"
        case .memories: return "brain"
        case .library: return "books.vertical"
        case .mcp: return "puzzlepiece"
        case .skills: return "star"
        case .search: return "magnifyingglass"
        case .permissions: return "lock.shield"
        case .connectors: return "link"
        case .performance: return "chart.bar"
        case .lora: return "cpu"
        case .advanced: return "slider.horizontal.3"
        }
    }
}
