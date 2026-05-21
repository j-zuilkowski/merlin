import Foundation

/// Persists completed `CalibrationReport`s to disk so a CLI consumer (or a
/// later in-app review surface) can read them without screen-scraping the
/// SwiftUI sheet.
///
/// Default destination is `~/.merlin/calibration/`. One JSON file per run,
/// filename `<localProviderID>-<ISO8601-dashed-timestamp>.json` — the
/// dashed timestamp keeps the filename POSIX-safe (no colons).
actor CalibrationReportSaver {

    let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder

    init(directory: URL = CalibrationReportSaver.defaultDirectory,
         fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    /// Writes `report` to disk and returns the URL of the written file.
    /// Creates the target directory if it doesn't yet exist.
    @discardableResult
    func save(_ report: CalibrationReport) throws -> URL {
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(at: directory,
                                            withIntermediateDirectories: true)
        }
        let filename = Self.filename(for: report)
        let url = directory.appendingPathComponent(filename)
        let data = try encoder.encode(report)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Default destination: `~/.merlin/calibration/`. Honours `$HOME`.
    static var defaultDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".merlin/calibration", isDirectory: true)
    }

    /// Builds the per-run filename. Format:
    ///   `<localProviderID>-<YYYY-MM-DDTHH-MM-SS>.json`
    /// ISO8601 with colons replaced by dashes so the filename works on any
    /// filesystem and is easy to parse in shell tooling.
    static func filename(for report: CalibrationReport) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        // Cut at the seconds boundary; ISO8601 trailing 'Z' stays.
        let raw = formatter.string(from: report.generatedAt)
        // Replace the time-section colons with dashes for POSIX safety.
        let safe = raw.replacingOccurrences(of: ":", with: "-")
        return "\(report.localProviderID)-\(safe).json"
    }
}
