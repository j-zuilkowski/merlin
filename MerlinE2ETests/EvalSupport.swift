import Foundation
import XCTest
@testable import Merlin

/// Resolves `merlin-eval/<...>` - the eval suite, which lives inside the `merlin` repo
/// at `merlin/merlin-eval/` - from this source file's location, so the harness needs no
/// env var or absolute path.
enum EvalPaths {
    /// `.../localProject`
    static var root: URL {
        URL(fileURLWithPath: #filePath)            // .../merlin/MerlinE2ETests/EvalSupport.swift
            .deletingLastPathComponent()           // .../merlin/MerlinE2ETests
            .deletingLastPathComponent()           // .../merlin
            .deletingLastPathComponent()           // .../localProject
    }
    static func fixture(_ name: String) -> String {
        root.appendingPathComponent("merlin/merlin-eval/fixtures/\(name)").path
    }
    static func sibling(_ name: String) -> String {
        root.appendingPathComponent(name).path     // e.g. "xcalibre-server"
    }
    static func fixtureExists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: fixture(name))
    }
}

/// Runs a shell command synchronously; returns combined stdout+stderr.
enum EvalShell {
    @discardableResult
    static func run(_ launchPath: String, _ args: [String],
                    cwd: String, env: [String: String] = [:]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd)
        if !env.isEmpty {
            var merged = ProcessInfo.processInfo.environment
            for (k, v) in env { merged[k] = v }
            proc.environment = merged
        }
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return "EvalShell launch error: \(error)" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }
}

/// Manages a long-running external service process for the proving suite - launch it,
/// wait until it answers, tear it down. The harness owns the service lifecycle so no
/// part of the suite is started by hand.
final class EvalService {
    private let process = Process()
    let label: String

    init(label: String) { self.label = label }

    /// Launches `executable` (a *built binary*, not a `cargo run` wrapper, so
    /// `terminate()` kills the real server rather than a parent shell).
    func launch(executable: String, args: [String] = [],
                cwd: String, env: [String: String] = [:]) throws {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var merged = ProcessInfo.processInfo.environment
        for (k, v) in env { merged[k] = v }
        process.environment = merged
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    /// Polls an HTTP `url` until it responds (any status) or `timeout` elapses.
    func waitUntilReady(url: String, timeout: TimeInterval) async -> Bool {
        guard let u = URL(string: url) else { return false }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (try? await URLSession.shared.data(from: u)) != nil { return true }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return false
    }

    var isRunning: Bool { process.isRunning }

    func terminate() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}

/// Resolves the LM Studio model to use - by capability, from Merlin's own config
/// (actual values, never invented). LM Studio's `[[providers]]` entry carries an empty
/// `model`; the model per role lives in `slotAssignments` as `"lmstudio:<modelID>"`,
/// so text vs vision is resolved from the slot, not the provider's bare `model` field.
enum EvalLMStudio {
    /// Merlin's configured LM Studio-backed providers.
    @MainActor
    static var providers: [ProviderConfig] {
        AppSettings.shared.providers.filter {
            $0.isLocal && ($0.id.contains("lmstudio") || $0.baseURL.contains(":1234"))
        }
    }

    /// The LM Studio provider with `model` filled in from role slot `slot` - the
    /// `[[providers]]` entry stores no model, so it is read from `slotAssignments`.
    @MainActor
    private static func resolved(slot: AgentSlot, vision: Bool) -> ProviderConfig? {
        guard let assigned = AppSettings.shared.slotAssignments[slot] else { return nil }
        let parts = assigned.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              var base = providers.first(where: { $0.id == String(parts[0]) })
        else { return nil }
        base.model = String(parts[1])
        base.supportsVision = vision
        return base
    }

    /// The LM Studio text model (S4 rerank, S5 LoRA base) - from the `execute` slot,
    /// falling back to `orchestrate`. `nil` when LM Studio is not slotted.
    @MainActor
    static func textProvider() -> ProviderConfig? {
        resolved(slot: .execute, vision: false)
            ?? resolved(slot: .orchestrate, vision: false)
    }

    /// The LM Studio vision model (S6 Part B schematic OCR) - from the `vision` slot.
    @MainActor
    static func visionProvider() -> ProviderConfig? {
        resolved(slot: .vision, vision: true)
    }

    /// Resolves an LM Studio model id (e.g. `qwen3-coder-next`) to its on-disk model
    /// directory. `mlx_lm.lora` needs a real path or a HuggingFace repo id — the LM
    /// Studio *alias* is neither. Both the models base directory and the per-model
    /// relative path are determined programmatically: the base from LM Studio's
    /// `settings.json` (`downloadsFolder`, which is user-configurable), the relative
    /// path from `lms ls --json`. Returns nil when nothing resolves on disk.
    static func localModelDirectory(forModelID modelID: String) -> String? {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let lmStudioHome = "\(home)/.lmstudio"

        // Models base directory — read from LM Studio's settings, never assumed.
        let modelsBase: String = {
            let settingsURL = URL(fileURLWithPath: "\(lmStudioHome)/settings.json")
            if FileManager.default.fileExists(atPath: settingsURL.path),
               let data = try? Data(contentsOf: settingsURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let folder = object["downloadsFolder"] as? String, !folder.isEmpty {
                return folder
            }
            return "\(lmStudioHome)/models"
        }()

        // Per-model relative path — read from the `lms` CLI's model index.
        let lms = "\(lmStudioHome)/bin/lms"
        guard FileManager.default.isExecutableFile(atPath: lms) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lms)
        process.arguments = ["ls", "--json"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let object = try? JSONSerialization.jsonObject(with: data)
        let entries = (object as? [[String: Any]])
            ?? ((object as? [String: Any])?["data"] as? [[String: Any]])
            ?? []
        guard let entry = entries.first(where: { ($0["modelKey"] as? String) == modelID }),
              let relativePath = entry["path"] as? String else { return nil }
        let fullPath = "\(modelsBase)/\(relativePath)"
        return FileManager.default.fileExists(atPath: fullPath) ? fullPath : nil
    }

    /// A model loaded in LM Studio, with the context length it was loaded at — both
    /// read from `lms ps --json` so a restore reproduces the exact load state.
    struct LoadedModel: Sendable {
        let key: String
        let contextLength: Int?
    }

    /// The models currently loaded in LM Studio's memory.
    static func loadedModels() -> [LoadedModel] {
        guard let output = runLMS(["ps", "--json"]),
              let object = try? JSONSerialization.jsonObject(with: Data(output.utf8)),
              let entries = object as? [[String: Any]] else { return [] }
        return entries.compactMap { entry in
            guard let key = (entry["modelKey"] as? String) ?? (entry["identifier"] as? String)
            else { return nil }
            return LoadedModel(key: key, contextLength: entry["contextLength"] as? Int)
        }
    }

    /// Unloads every model from LM Studio's memory (frees RAM for an out-of-process
    /// trainer; best-effort).
    static func unloadAllModels() {
        _ = runLMS(["unload", "--all"])
    }

    /// Loads the given models back into LM Studio at their captured context length.
    /// Blocks until each load completes so a later scenario finds the model ready.
    static func loadModels(_ models: [LoadedModel]) {
        for model in models {
            var args = ["load", model.key]
            if let context = model.contextLength {
                args += ["-c", String(context)]
            }
            _ = runLMS(args)
        }
    }

    /// Runs the LM Studio `lms` CLI, returning combined stdout (nil when `lms` is absent).
    private static func runLMS(_ args: [String]) -> String? {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        let lms = "\(home)/.lmstudio/bin/lms"
        guard FileManager.default.isExecutableFile(atPath: lms) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: lms)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

/// Appends a scenario's captured run to `merlin/merlin-eval/results/` - every value logged end
/// to end (SURFACE-CENSUS.md -> "Evidence & end-to-end value logging").
enum EvalLog {
    static func write(scenario: String, summary: String) {
        let dir = EvalPaths.root.appendingPathComponent("merlin/merlin-eval/results")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        try? summary.write(to: dir.appendingPathComponent("\(scenario)-harness-\(stamp).md"),
                           atomically: true, encoding: .utf8)
    }
}

/// The exact scenario prompts (kept identical to the scenario files).
enum EvalPrompts {
    static let s1 = """
    The macOS app at this project path is a SwiftUI task list called TaskBoard. Build \
    it, launch it, and use it the way a user would: add tasks, mark some done, delete \
    one, open the Stats window, click every toolbar button. It has logic and visual \
    defects. Find every defect by exercising the running app, fix each in the source, \
    rebuild, and re-verify. Report each defect, the fix, and how you confirmed it.
    """
    static let s2 = """
    The Rust project at this project path is an expense-ledger library and CLI. Build \
    it, run `cargo test`, exercise the CLI. It has logic, error-handling, and \
    concurrency bugs. Find every defect, fix it, and re-verify until `cargo test` is \
    green. Report each defect, root cause, fix, and how you confirmed it.
    """
    static let s4 = """
    Using the connected knowledge base, answer and cite each: (1) At what pressure does \
    the Glimworks Mark IV operate? (2) How long is its calibration cycle and what is \
    the reset code? (3) Who founded Glimworks Industries and in what city? (4) What is \
    the Mark IV's maximum rotational speed?
    """
    static let s6 = """
    Design a 555-timer astable LED blinker in this project: NE555 (U1), R1 10k, R2 47k, \
    C1 10uF, C2 10nF, R3 330, an LED (D1), 5V supply, standard astable. Create the \
    KiCad schematic, assign footprints, lay out the PCB, route it with FreeRouting, and \
    run an ngspice simulation confirming the output oscillates. Report the netlist, the \
    routing result, and the simulated blink frequency vs the ~1.4 Hz target.
    """

    static func s6OCR(imagePath: String) -> String {
        """
        Import the schematic image at \(imagePath). Extract its components and netlist \
        into a KiCad schematic. Report every component you recognised (designator + \
        value) and the connections between them, and flag anything you could not read.
        """
    }
}
