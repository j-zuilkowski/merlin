import Foundation
import Darwin

// MARK: - TelemetryValue

/// Typed JSON-serialisable value for telemetry data dictionaries.
/// Supports literal syntax at call sites: `"deepseek"`, `14068`, `3.14`, `true`.
public enum TelemetryValue: Encodable, Sendable,
    ExpressibleByStringLiteral,
    ExpressibleByIntegerLiteral,
    ExpressibleByFloatLiteral,
    ExpressibleByBooleanLiteral {

    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    public init(stringLiteral value: String)  { self = .string(value) }
    public init(integerLiteral value: Int)    { self = .int(value) }
    public init(floatLiteral value: Double)   { self = .double(value) }
    public init(booleanLiteral value: Bool)   { self = .bool(value) }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i):    try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b):   try c.encode(b)
        case .null:          try c.encodeNil()
        }
    }
}

// MARK: - TelemetryEvent

/// A single structured diagnostic event written as one JSON line.
public struct TelemetryEvent: Encodable, Sendable {
    public var ts: Date
    public var sessionID: String
    public var turn: Int
    public var loop: Int
    public var event: String
    public var durationMs: Double?
    public var data: [String: TelemetryValue]

    enum CodingKeys: String, CodingKey {
        case ts, turn, loop, event, data
        case sessionID  = "session_id"
        case durationMs = "duration_ms"
    }

    public init(ts: Date, sessionID: String, turn: Int, loop: Int,
                event: String, durationMs: Double? = nil,
                data: [String: TelemetryValue] = [:]) {
        self.ts = ts
        self.sessionID = sessionID
        self.turn = turn
        self.loop = loop
        self.event = event
        self.durationMs = durationMs
        self.data = data
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try c.encode(formatter.string(from: ts), forKey: .ts)
        try c.encode(sessionID, forKey: .sessionID)
        try c.encode(turn,      forKey: .turn)
        try c.encode(loop,      forKey: .loop)
        try c.encode(event,     forKey: .event)
        try c.encodeIfPresent(durationMs, forKey: .durationMs)
        if !data.isEmpty { try c.encode(data, forKey: .data) }
    }
}

// MARK: - TelemetrySpan

/// Tracks the start time of an operation; call `finish(data:)` to emit the event with duration.
public final class TelemetrySpan: Sendable {
    private let event: String
    private let startedAt: Date
    private let startData: [String: TelemetryValue]

    init(event: String, startData: [String: TelemetryValue]) {
        self.event = event
        self.startedAt = Date()
        self.startData = startData
    }

    /// Emit the span event with elapsed `duration_ms`. Merges start and finish data.
    public func finish(data: [String: Any] = [:]) {
        let ms = Date().timeIntervalSince(startedAt) * 1000
        let merged = startData.merging(TelemetryEmitter.shared.normalizeData(data)) { _, new in new }
        TelemetryEmitter.shared.emitNormalized(event, durationMs: ms, data: merged)
    }
}

// MARK: - TelemetryEmitter

/// Singleton that writes structured JSON-line telemetry to `~/.merlin/telemetry.jsonl`.
/// All file I/O is performed on a background serial queue - `emit()` never blocks the caller.
/// If the file cannot be opened, events are silently dropped (telemetry is best-effort).
public final class TelemetryEmitter: @unchecked Sendable {

    public static let shared = TelemetryEmitter()

    // Current context - written from @MainActor, read from background queue (best-effort).
    public private(set) var sessionID: String = UUID().uuidString
    public private(set) var turn: Int = 0
    public private(set) var loop: Int = 0

    private let queue = DispatchQueue(label: "com.merlin.telemetry", qos: .utility)
    private var filePath: String
    private var maxBytes: Int
    private var fileHandle: FileHandle?
    private var encoder: JSONEncoder

    private static let defaultPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.merlin/telemetry.jsonl"
    }()

    private init() {
        self.filePath = Self.defaultPath
        self.maxBytes = 10 * 1024 * 1024 // 10 MB
        self.encoder = JSONEncoder()
        queue.async { [weak self] in self?.openFile() }
    }

    // MARK: Context

    /// Called from @MainActor to update the current session/turn/loop context.
    public func setContext(sessionID: String, turn: Int, loop: Int) {
        self.sessionID = sessionID
        self.turn      = turn
        self.loop      = loop
    }

    public func setSession(_ id: String) { sessionID = id }
    public func setTurn(_ t: Int)        { turn = t }
    public func setLoop(_ l: Int)        { loop = l }

    // MARK: Emit

    /// Fire-and-forget event. Never blocks the caller.
    public func emit(_ event: String,
                     durationMs: Double? = nil,
                     data: [String: Any] = [:]) {
        let normalizedData = normalizeData(data)
        emitNormalized(event, durationMs: durationMs, data: normalizedData)
    }

    fileprivate func emitNormalized(_ event: String,
                                    durationMs: Double? = nil,
                                    data: [String: TelemetryValue] = [:]) {
        let e = TelemetryEvent(
            ts: Date(),
            sessionID: sessionID,
            turn: turn,
            loop: loop,
            event: event,
            durationMs: durationMs,
            data: data
        )
        queue.async { [weak self] in self?.write(e) }
    }

    /// Open a timing span. Call `span.finish(data:)` to emit with duration.
    public func begin(_ event: String,
                      data: [String: Any] = [:]) -> TelemetrySpan {
        TelemetrySpan(event: event, startData: normalizeData(data))
    }

    /// Sample and emit current process RSS and virtual memory usage.
    /// Uses `task_info` - available on macOS without entitlements.
    public func emitProcessMemory() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }
        let rssMB = Double(info.resident_size) / 1_048_576
        let vsizeMB = Double(info.virtual_size) / 1_048_576
        emit("process.memory", data: [
            "rss_mb": rssMB,
            "vsize_mb": vsizeMB
        ])
    }

    /// Emit a GUI interaction event. Call from SwiftUI button/field action closures.
    /// - Parameters:
    ///   - action: Short verb describing the interaction: `"tap"`, `"focus"`, `"dismiss"`.
    ///   - identifier: The `AccessibilityID` constant for the control.
    public func emitGUIAction(_ action: String, identifier: String) {
        emit("gui.action", data: [
            "action": action,
            "identifier": identifier
        ])
    }

    // MARK: Private file I/O (runs on `queue`)

    private func openFile() {
        let url = URL(fileURLWithPath: filePath)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: filePath) {
            FileManager.default.createFile(atPath: filePath, contents: nil)
        }
        fileHandle = try? FileHandle(forWritingTo: url)
        fileHandle?.seekToEndOfFile()
    }

    private func write(_ event: TelemetryEvent) {
        guard let data = try? encoder.encode(event) else { return }
        var line = data
        line.append(0x0A) // newline

        // Rotate if needed
        if let fh = fileHandle,
           fh.offsetInFile + UInt64(line.count) > UInt64(maxBytes) {
            rotate()
        }

        if fileHandle == nil { openFile() }
        fileHandle?.write(line)
    }

    private func rotate() {
        fileHandle?.closeFile()
        fileHandle = nil
        let rotated = filePath.replacingOccurrences(of: ".jsonl", with: ".1.jsonl")
        try? FileManager.default.removeItem(atPath: rotated)
        try? FileManager.default.moveItem(atPath: filePath, toPath: rotated)
    }

    // MARK: Testing support

    /// Redirect output and reset state. Call from test setUp only.
    public func resetForTesting(path: String, maxBytes: Int = 10 * 1024 * 1024) async {
        await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                self.fileHandle?.closeFile()
                self.fileHandle = nil
                self.filePath = path
                self.maxBytes = maxBytes
                self.sessionID = UUID().uuidString
                self.turn = 0
                self.loop = 0
                continuation.resume()
            }
        }
    }

    /// Block until all queued writes complete. Tests only.
    public func flushForTesting() async {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume() }
        }
    }

    fileprivate func normalizeData(_ data: [String: Any]) -> [String: TelemetryValue] {
        var normalized: [String: TelemetryValue] = [:]
        normalized.reserveCapacity(data.count)
        for (key, value) in data {
            normalized[key] = normalizeValue(value)
        }
        return normalized
    }

    private func normalizeValue(_ value: Any) -> TelemetryValue {
        if let telemetryValue = value as? TelemetryValue {
            return telemetryValue
        }
        if let stringValue = value as? String {
            return .string(stringValue)
        }
        if let intValue = value as? Int {
            return .int(intValue)
        }
        if let doubleValue = value as? Double {
            return .double(doubleValue)
        }
        if let boolValue = value as? Bool {
            return .bool(boolValue)
        }
        if value is NSNull {
            return .null
        }
        return .string(String(describing: value))
    }
}
