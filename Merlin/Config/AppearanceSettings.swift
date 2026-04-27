import Foundation
import SwiftUI

enum AppTheme: String, CaseIterable, Codable, Sendable {
    case system
    case light
    case dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct AppearanceSettings: Codable, Sendable {
    var theme: AppTheme = .system
    var fontSize: Double = 13.0
    var fontName: String = "SF Mono"
    var accentColorHex: String = ""
    var lineSpacing: Double = 4.0

    enum CodingKeys: String, CodingKey {
        case theme
        case fontSize = "font_size"
        case fontName = "font_name"
        case accentColorHex = "accent_color_hex"
        case lineSpacing = "line_spacing"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme) ?? .system
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13.0
        fontName = try container.decodeIfPresent(String.self, forKey: .fontName) ?? "SF Mono"
        accentColorHex = try container.decodeIfPresent(String.self, forKey: .accentColorHex) ?? ""
        lineSpacing = try container.decodeIfPresent(Double.self, forKey: .lineSpacing) ?? 4.0
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(theme, forKey: .theme)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontName, forKey: .fontName)
        try container.encode(accentColorHex, forKey: .accentColorHex)
        try container.encode(lineSpacing, forKey: .lineSpacing)
    }
}
