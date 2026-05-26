import Foundation

/// Writes JSON design artifacts produced by the pipeline tools.
enum Artifacts {
    /// Writes `object` as pretty JSON to `named`, in the directory of `besides`
    /// (or the temp directory when `besides` is empty/unusable). Returns the path.
    static func write(_ object: [String: Any], named: String, besides: String) -> String? {
        let directory: String
        if besides.isEmpty {
            directory = NSTemporaryDirectory()
        } else {
            let url = URL(fileURLWithPath: besides)
            directory = url.hasDirectoryPath
                ? url.path
                : url.deletingLastPathComponent().path
        }
        let path = URL(fileURLWithPath: directory).appendingPathComponent(named).path
        guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                     options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        do {
            try FileManager.default.createDirectory(atPath: directory,
                                                    withIntermediateDirectories: true)
            try data.write(to: URL(fileURLWithPath: path))
            return path
        } catch {
            return nil
        }
    }
}

/// Materializes and inspects KiCad project files.
enum KiCadProject {

    enum ReportKind { case erc, drc }

    enum ProjectError: Error, LocalizedError {
        case writeFailed(String)
        var errorDescription: String? {
            switch self {
            case .writeFailed(let path): return "could not write \(path)"
            }
        }
    }

    /// Writes a valid, empty KiCad project (`.kicad_pro` / `.kicad_sch` / `.kicad_pcb`)
    /// into `directory`. Component-level schematic capture is layered on by the
    /// downstream pipeline tools; this is the materialized starting point.
    static func materialize(in directory: String, name: String) throws -> [String] {
        let fm = FileManager.default
        try fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let base = URL(fileURLWithPath: directory)
        let proURL = base.appendingPathComponent("\(name).kicad_pro")
        let schURL = base.appendingPathComponent("\(name).kicad_sch")
        let pcbURL = base.appendingPathComponent("\(name).kicad_pcb")

        try write(projectFile(name: name), to: proURL)
        try write(schematicFile(uuid: UUID().uuidString), to: schURL)
        try write(boardFile(uuid: UUID().uuidString), to: pcbURL)
        return [proURL.path, schURL.path, pcbURL.path]
    }

    /// Finds a project file with extension `ext`. `projectPath` may be a directory, a
    /// `.kicad_pro` file, or any sibling project file.
    static func locate(projectPath: String, ext: String) -> String? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: projectPath, isDirectory: &isDir) else {
            // projectPath may itself be the target file that does not yet exist —
            // try swapping the extension on a sibling.
            let swapped = URL(fileURLWithPath: projectPath).deletingPathExtension()
                .appendingPathExtension(ext).path
            return fm.fileExists(atPath: swapped) ? swapped : nil
        }
        if !isDir.boolValue {
            if projectPath.hasSuffix(".\(ext)") { return projectPath }
            let swapped = URL(fileURLWithPath: projectPath).deletingPathExtension()
                .appendingPathExtension(ext).path
            return fm.fileExists(atPath: swapped) ? swapped : nil
        }
        let entries = (try? fm.contentsOfDirectory(atPath: projectPath)) ?? []
        guard let match = entries.first(where: { $0.hasSuffix(".\(ext)") }) else { return nil }
        return URL(fileURLWithPath: projectPath).appendingPathComponent(match).path
    }

    /// Runs ERC or DRC via `kicad-cli` and returns a `KiCadToolResult`-shaped JSON string.
    static func runReport(projectPath: String, kind: ReportKind) -> String {
        let ext = (kind == .erc) ? "kicad_sch" : "kicad_pcb"
        let label = (kind == .erc) ? "ERC" : "DRC"
        guard let file = locate(projectPath: projectPath, ext: ext) else {
            return KiCadTools.result(
                status: "failed",
                summary: "No .\(ext) found for \(projectPath). Run kicad_compile_project first.")
        }
        let reportPath = NSTemporaryDirectory()
            + "kicad-\(label.lowercased())-\(UUID().uuidString).json"
        let subcommand = (kind == .erc) ? ["sch", "erc"] : ["pcb", "drc"]
        guard let cli = KiCadCLI.cli(subcommand + [file, "-o", reportPath, "--format", "json"]) else {
            return KiCadTools.result(
                status: "blocked_tooling",
                summary: "kicad-cli not found — install KiCad 10+ to run \(label).")
        }
        let reportText = (try? String(contentsOfFile: reportPath, encoding: .utf8)) ?? ""
        let violations = countViolations(in: reportText)
        if cli.exitCode < 0 {
            return KiCadTools.result(
                status: "failed",
                summary: "kicad-cli \(label) could not run.",
                warnings: [KiCadTools.warning("KICAD_CLI_FAILED", cli.stderr)])
        }
        return KiCadTools.result(
            status: "complete",
            summary: "\(label) complete: \(violations) violation(s).",
            artifacts: FileManager.default.fileExists(atPath: reportPath) ? [reportPath] : [],
            metrics: ["violations": Double(violations)])
    }

    // MARK: - Private

    private static func countViolations(in reportJSON: String) -> Int {
        guard let data = reportJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return 0
        }
        if let violations = object["violations"] as? [[String: Any]] {
            return violations.count
        }
        if let sheets = object["sheets"] as? [[String: Any]] {
            return sheets.reduce(0) { $0 + (($1["violations"] as? [[String: Any]])?.count ?? 0) }
        }
        return 0
    }

    private static func write(_ contents: String, to url: URL) throws {
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ProjectError.writeFailed(url.path)
        }
    }

    private static func projectFile(name: String) -> String {
        """
        {
          "board": {"design_settings": {}, "layer_presets": [], "viewports": []},
          "boards": [],
          "cvpcb": {"equivalence_files": []},
          "libraries": {"pinned_footprint_libs": [], "pinned_symbol_libs": []},
          "meta": {"filename": "\(name).kicad_pro", "version": 1},
          "net_settings": {"classes": [{"name": "Default", "clearance": 0.2, "track_width": 0.25}]},
          "pcbnew": {"last_paths": {}, "page_layout_descr_file": ""},
          "schematic": {"legacy_lib_dir": "", "legacy_lib_list": []},
          "sheets": [],
          "text_variables": {}
        }
        """
    }

    private static func schematicFile(uuid: String) -> String {
        """
        (kicad_sch
        \t(version 20231120)
        \t(generator "merlin-kicad-mcp")
        \t(uuid "\(uuid)")
        \t(paper "A4")
        \t(lib_symbols)
        \t(sheet_instances
        \t\t(path "/"
        \t\t\t(page "1")
        \t\t)
        \t)
        )
        """
    }

    private static func boardFile(uuid: String) -> String {
        """
        (kicad_pcb
        \t(version 20240108)
        \t(generator "merlin-kicad-mcp")
        \t(general
        \t\t(thickness 1.6)
        \t)
        \t(paper "A4")
        \t(layers
        \t\t(0 "F.Cu" signal)
        \t\t(31 "B.Cu" signal)
        \t\t(37 "F.SilkS" user "F.Silkscreen")
        \t\t(36 "B.SilkS" user "B.Silkscreen")
        \t\t(44 "Edge.Cuts" user)
        \t)
        \t(setup
        \t\t(pad_to_mask_clearance 0)
        \t)
        \t(net 0 "")
        )
        """
    }
}
