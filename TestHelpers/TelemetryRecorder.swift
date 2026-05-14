import Foundation
@testable import Merlin

final class TelemetryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var events: [TelemetryEvent] = []

    func record(_ event: TelemetryEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func clear() {
        lock.lock()
        events.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

extension TelemetryValue {
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        if case .int(let value) = self { return value }
        return nil
    }
}
