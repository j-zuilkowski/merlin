import Foundation
@testable import Merlin

final class TelemetryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var events: [TelemetryEvent] = []

    init() {
        if TelemetryEmitter.sink == nil {
            TelemetryEmitter.sink = self
        }
    }

    deinit {
        if let current = TelemetryEmitter.sink as? TelemetryRecorder, current === self {
            TelemetryEmitter.sink = nil
        }
    }

    func store(_ event: TelemetryEvent) {
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

extension TelemetryRecorder: TelemetrySink {
    func record(_ event: TelemetryEvent) {
        store(event)
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
