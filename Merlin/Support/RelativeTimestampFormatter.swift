import Foundation

enum RelativeTimestampFormatter {
    static func string(from date: Date, now: Date = Date()) -> String {
        let interval = max(0, now.timeIntervalSince(date))
        switch interval {
        case ..<60:      return "now"
        case ..<3600:    return "\(Int(interval / 60))m"
        case ..<86400:   return "\(Int(interval / 3600))h"
        case ..<604800:  return "\(Int(interval / 86400))d"
        default:         return "\(Int(interval / 604800))w"
        }
    }
}
