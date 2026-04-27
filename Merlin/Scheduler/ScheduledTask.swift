import Foundation

enum Weekday: Int, Codable, Sendable, CaseIterable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    var displayName: String {
        [
            "Sunday",
            "Monday",
            "Tuesday",
            "Wednesday",
            "Thursday",
            "Friday",
            "Saturday"
        ][rawValue - 1]
    }
}

enum ScheduleCadence: Codable, Sendable, Equatable {
    case daily
    case weekly(Weekday)
    case hourly

    enum CodingKeys: String, CodingKey {
        case type
        case weekday
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "daily":
            self = .daily
        case "hourly":
            self = .hourly
        case "weekly":
            let weekday = try container.decode(Weekday.self, forKey: .weekday)
            self = .weekly(weekday)
        default:
            self = .daily
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try container.encode("daily", forKey: .type)
        case .hourly:
            try container.encode("hourly", forKey: .type)
        case .weekly(let weekday):
            try container.encode("weekly", forKey: .type)
            try container.encode(weekday, forKey: .weekday)
        }
    }
}

struct ScheduledTask: Identifiable, Codable, Sendable {
    var id: UUID
    var name: String
    var cadence: ScheduleCadence
    var time: String
    var projectPath: String
    var permissionMode: PermissionMode
    var prompt: String
    var isEnabled: Bool

    init(id: UUID = UUID(),
         name: String,
         cadence: ScheduleCadence,
         time: String,
         projectPath: String,
         permissionMode: PermissionMode,
         prompt: String,
         isEnabled: Bool) {
        self.id = id
        self.name = name
        self.cadence = cadence
        self.time = time
        self.projectPath = projectPath
        self.permissionMode = permissionMode
        self.prompt = prompt
        self.isEnabled = isEnabled
    }
}
