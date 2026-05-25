import Foundation

struct WorkspaceLayout: Codable, Sendable {
    var showDiffPane: Bool
    var showFilePane: Bool
    var showTerminalPane: Bool
    var showPreviewPane: Bool
    var showSideChat: Bool
    var showCAGPane: Bool
    var sidebarWidth: Double
    var chatWidth: Double

    enum CodingKeys: String, CodingKey {
        case showDiffPane = "show_diff_pane"
        case showFilePane = "show_file_pane"
        case showTerminalPane = "show_terminal_pane"
        case showPreviewPane = "show_preview_pane"
        case showSideChat = "show_side_chat"
        case showCAGPane = "show_cag_pane"
        case sidebarWidth = "sidebar_width"
        case chatWidth = "chat_width"
    }

    init(
        showDiffPane: Bool,
        showFilePane: Bool,
        showTerminalPane: Bool,
        showPreviewPane: Bool,
        showSideChat: Bool,
        showCAGPane: Bool,
        sidebarWidth: Double,
        chatWidth: Double
    ) {
        self.showDiffPane = showDiffPane
        self.showFilePane = showFilePane
        self.showTerminalPane = showTerminalPane
        self.showPreviewPane = showPreviewPane
        self.showSideChat = showSideChat
        self.showCAGPane = showCAGPane
        self.sidebarWidth = sidebarWidth
        self.chatWidth = chatWidth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        showDiffPane = try c.decodeIfPresent(Bool.self, forKey: .showDiffPane) ?? false
        showFilePane = try c.decodeIfPresent(Bool.self, forKey: .showFilePane) ?? true
        showTerminalPane = try c.decodeIfPresent(Bool.self, forKey: .showTerminalPane) ?? false
        showPreviewPane = try c.decodeIfPresent(Bool.self, forKey: .showPreviewPane) ?? false
        showSideChat = try c.decodeIfPresent(Bool.self, forKey: .showSideChat) ?? false
        showCAGPane = try c.decodeIfPresent(Bool.self, forKey: .showCAGPane) ?? false
        sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? 200
        chatWidth = try c.decodeIfPresent(Double.self, forKey: .chatWidth) ?? 300
    }
}

struct WorkspaceLayoutManager: Sendable {
    let url: URL

    static var defaultLayout: WorkspaceLayout {
        WorkspaceLayout(
            showDiffPane: false,
            showFilePane: true,
            showTerminalPane: false,
            showPreviewPane: false,
            showSideChat: false,
            showCAGPane: false,
            sidebarWidth: 200,
            chatWidth: 300
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
