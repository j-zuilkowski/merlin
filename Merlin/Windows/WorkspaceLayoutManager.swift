import Foundation

struct WorkspaceLayout: Codable, Sendable {
    var showFilePane: Bool
    var showTerminalPane: Bool
    var showPreviewPane: Bool
    var showSideChat: Bool
    var sidebarWidth: Double
    var chatWidth: Double

    enum CodingKeys: String, CodingKey {
        case showFilePane = "show_file_pane"
        case showTerminalPane = "show_terminal_pane"
        case showPreviewPane = "show_preview_pane"
        case showSideChat = "show_side_chat"
        case sidebarWidth = "sidebar_width"
        case chatWidth = "chat_width"
    }
}

struct WorkspaceLayoutManager: Sendable {
    let url: URL

    static var defaultLayout: WorkspaceLayout {
        WorkspaceLayout(
            showFilePane: true,
            showTerminalPane: false,
            showPreviewPane: false,
            showSideChat: false,
            sidebarWidth: 200,
            chatWidth: 520
        )
    }

    func load() throws -> WorkspaceLayout {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return Self.defaultLayout
        }

        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(WorkspaceLayout.self, from: data)
    }

    func save(_ layout: WorkspaceLayout) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(layout)
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
