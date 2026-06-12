import Foundation
import AppKit

/// Loads an image file as JPEG data (the format the vision API expects). Returns
/// the bytes unchanged when already JPEG; converts PNG/other formats via NSImage.
private func loadImageAsJPEG(_ path: String) -> Data? {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
    if data.starts(with: [0xFF, 0xD8, 0xFF]) { return data }
    guard let image = NSImage(data: data),
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    else { return nil }
    return jpeg
}

@MainActor
func registerAllTools(
    router: ToolRouter,
    defaultProjectPath: String? = nil,
    visionProvider: @escaping @MainActor () -> (any LLMProvider)? = { nil }
) {
    // MARK: File System
    router.register(name: "read_file") { args in
        let a = try decode(args, as: PathArgs.self)
        let scoped = BuiltInToolScope.resolvePath(a.path, defaultProjectPath: defaultProjectPath)
        let output = try await FileSystemTools.readFile(path: scoped.path)
        return ToolOutput.clamp(scoped.prefixed(output))
    }
    router.register(name: "write_file") { args in
        let a = try decode(args, as: WriteFileArgs.self)
        let scoped = BuiltInToolScope.resolvePath(a.path, defaultProjectPath: defaultProjectPath)
        try await FileSystemTools.writeFile(path: scoped.path, content: a.content)
        return scoped.prefixed("Written")
    }
    router.register(name: "create_file") { args in
        let a = try decode(args, as: PathArgs.self)
        let scoped = BuiltInToolScope.resolvePath(a.path, defaultProjectPath: defaultProjectPath)
        try await FileSystemTools.createFile(path: scoped.path)
        return scoped.prefixed("Created")
    }
    router.register(name: "delete_file") { args in
        let a = try decode(args, as: PathArgs.self)
        let scoped = BuiltInToolScope.resolvePath(a.path, defaultProjectPath: defaultProjectPath)
        try await FileSystemTools.deleteFile(path: scoped.path)
        return scoped.prefixed("Deleted")
    }
    router.register(name: "list_directory") { args in
        let a = try decode(args, as: ListDirectoryArgs.self)
        let scoped = BuiltInToolScope.resolvePath(a.path, defaultProjectPath: defaultProjectPath)
        let output = try await FileSystemTools.listDirectory(path: scoped.path, recursive: a.recursive ?? false)
        return scoped.prefixed(output)
    }
    router.register(name: "move_file") { args in
        let a = try decode(args, as: MoveFileArgs.self)
        let src = BuiltInToolScope.resolvePath(a.src, defaultProjectPath: defaultProjectPath)
        let dst = BuiltInToolScope.resolvePath(a.dst, defaultProjectPath: defaultProjectPath)
        try await FileSystemTools.moveFile(src: src.path, dst: dst.path)
        return src.mergingWarning(with: dst).prefixed("Moved")
    }
    router.register(name: "search_files") { args in
        let a = try decode(args, as: SearchFilesArgs.self)
        let scoped = BuiltInToolScope.resolvePath(a.path, defaultProjectPath: defaultProjectPath)
        let output = try await FileSystemTools.searchFiles(path: scoped.path, pattern: a.pattern, contentPattern: a.contentPattern)
        return ToolOutput.clamp(scoped.prefixed(output))
    }

    // MARK: Shell
    router.register(name: "run_shell") { args in
        let a = try decode(args, as: RunShellArgs.self)
        let scoped = BuiltInToolScope.resolveCWD(a.cwd, defaultProjectPath: defaultProjectPath)
        let result = try await ShellTool.run(
            command: a.command,
            cwd: scoped.path,
            timeoutSeconds: a.timeoutSeconds ?? 120
        )
        let output = "exit:\(result.exitCode)\nstdout:\(result.stdout)\nstderr:\(result.stderr)"
        return ToolOutput.clamp(scoped.prefixed(output))
    }
    // Alias for models trained on Claude computer-use format (e.g. DeepSeek V4 Pro)
    router.register(name: "bash") { args in
        let a = try decode(args, as: RunShellArgs.self)
        let scoped = BuiltInToolScope.resolveCWD(a.cwd, defaultProjectPath: defaultProjectPath)
        let result = try await ShellTool.run(
            command: a.command,
            cwd: scoped.path,
            timeoutSeconds: a.timeoutSeconds ?? 120
        )
        let output = "exit:\(result.exitCode)\nstdout:\(result.stdout)\nstderr:\(result.stderr)"
        return ToolOutput.clamp(scoped.prefixed(output))
    }

    // MARK: App Control
    router.register(name: "app_launch") { args in
        let a = try decode(args, as: LaunchAppArgs.self)
        try AppControlTools.launch(bundleID: a.bundleId, arguments: a.arguments ?? [])
        return "Launched"
    }
    router.register(name: "app_list_running") { _ in
        let apps = AppControlTools.listRunning()
        return apps.map { "\($0.bundleID) (\($0.name))" }.joined(separator: "\n")
    }
    router.register(name: "app_quit") { args in
        let a = try decode(args, as: BundleIDArgs.self)
        try AppControlTools.quit(bundleID: a.bundleId)
        return "Quit"
    }
    router.register(name: "app_focus") { args in
        let a = try decode(args, as: BundleIDArgs.self)
        try AppControlTools.focus(bundleID: a.bundleId)
        return "Focused"
    }

    // MARK: Tool Discovery
    router.register(name: "tool_discover") { args in
        let request = try? decode(args, as: ToolDiscovery.Request.self)
        let tools = await ToolDiscovery.cachedScan(
            requestedTool: request?.requestedName,
            summarize: false
        )
        return tools.map { "\($0.name): \($0.path)" }.joined(separator: "\n")
    }

    // MARK: Knowledge
    router.register(name: "rag_search") { _ in
        "RAG service not configured."
    }
    router.register(name: "rag_list_books") { _ in
        "RAG service not configured."
    }

    // MARK: Discipline
    router.register(name: "generate_api_docs") { args in
        let a = try decode(args, as: ProjectPathArgs.self)
        let path = a.projectPath ?? AppSettings.shared.projectPath
        let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: path)
        let out = try await APIDocGenerator().generate(projectPath: path, adapter: adapter)
        return "API docs generated: \(out)"
    }
    router.register(name: "generate_dev_guide") { args in
        let a = try decode(args, as: ProjectPathArgs.self)
        let path = a.projectPath ?? AppSettings.shared.projectPath
        let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: path)
        try await DevGuideGenerator().generate(projectPath: path, adapter: adapter)
        return "Developer guide updated."
    }
    router.register(name: "write_vale_styles") { args in
        let a = try decode(args, as: ProjectPathArgs.self)
        let path = a.projectPath ?? AppSettings.shared.projectPath
        try await ValeStyleWriter().writeStyles(to: path + "/.vale/styles")
        return "Vale styles written to .vale/styles."
    }
    router.register(name: "scaffold_manual_coverage") { args in
        let a = try decode(args, as: ProjectPathArgs.self)
        let path = a.projectPath ?? AppSettings.shared.projectPath
        let adapter = await DisciplineEngine.resolveProjectAdapter(projectPath: path)
        let gaps = await ManualCoverageScanner().scan(projectPath: path, adapter: adapter)
        let writer = ManualSectionTemplateWriter()
        for gap in gaps {
            try await writer.write(gap: gap, to: path + "/docs/manual-coverage.md")
        }
        return "Scaffolded \(gaps.count) manual-coverage section(s)."
    }

    // MARK: Xcode
    router.register(name: "xcode_build") { args in
        let a = try decode(args, as: XcodeBuildArgs.self)
        let result = try await XcodeTools.build(
            scheme: a.scheme,
            configuration: a.configuration,
            destination: a.destination
        )
        return result.stdout + result.stderr
    }
    router.register(name: "xcode_test") { args in
        let a = try decode(args, as: XcodeTestArgs.self)
        let result = try await XcodeTools.test(scheme: a.scheme, testID: a.testId)
        return result.stdout + result.stderr
    }
    router.register(name: "xcode_clean") { _ in
        let result = try await XcodeTools.clean()
        return result.stdout + result.stderr
    }
    router.register(name: "xcode_derived_data_clean") { _ in
        try await XcodeTools.cleanDerivedData()
        return "Cleaned DerivedData"
    }
    router.register(name: "xcode_open_file") { args in
        let a = try decode(args, as: XcodeOpenFileArgs.self)
        try await XcodeTools.openFile(path: a.path, line: a.line)
        return "Opened"
    }
    router.register(name: "xcode_xcresult_parse") { args in
        let a = try decode(args, as: PathArgs.self)
        let summary = try XcodeTools.parseXcresult(path: a.path ?? "")
        let failures = summary.testFailures ?? []
        guard failures.isEmpty == false else {
            return "No failures"
        }
        return failures.map { "\($0.testName): \($0.message)" }.joined(separator: "\n")
    }
    router.register(name: "xcode_simulator_list") { _ in
        try await XcodeTools.simulatorList()
    }
    router.register(name: "xcode_simulator_boot") { args in
        let a = try decode(args, as: UdidArgs.self)
        try await XcodeTools.simulatorBoot(udid: a.udid)
        return "Booted"
    }
    router.register(name: "xcode_simulator_screenshot") { args in
        let a = try decode(args, as: UdidArgs.self)
        let data = try await XcodeTools.simulatorScreenshot(udid: a.udid)
        return "PNG: \(data.count) bytes"
    }
    router.register(name: "xcode_simulator_install") { args in
        let a = try decode(args, as: SimulatorInstallArgs.self)
        try await XcodeTools.simulatorInstall(udid: a.udid, appPath: a.appPath)
        return "Installed"
    }
    router.register(name: "xcode_spm_resolve") { args in
        let a = try decode(args, as: CwdArgs.self)
        let result = try await XcodeTools.spmResolve(cwd: a.cwd ?? ".")
        return result.stdout + result.stderr
    }
    router.register(name: "xcode_spm_list") { args in
        let a = try decode(args, as: CwdArgs.self)
        let result = try await XcodeTools.spmList(cwd: a.cwd ?? ".")
        return result.stdout + result.stderr
    }

    // MARK: AX / GUI Inspect
    router.register(name: "ui_inspect") { args in
        let a = try decode(args, as: BundleIDArgs.self)
        let tree = await AXInspectorTool.probe(bundleID: a.bundleId)
        return tree.toJSON()
    }
    router.register(name: "ui_find_element") { args in
        let a = try decode(args, as: FindElementArgs.self)
        guard let element = await AXInspectorTool.findElement(
            bundleID: a.bundleId,
            role: a.role,
            label: a.label,
            value: a.value
        ) else {
            return "Not found"
        }
        return "frame:\(element.frame) label:\(element.label ?? "-")"
    }
    router.register(name: "ui_get_element_value") { args in
        let a = try decode(args, as: ElementValueArgs.self)
        guard let element = await AXInspectorTool.findElement(
            bundleID: a.bundleId,
            role: nil,
            label: a.label,
            value: nil
        ) else {
            return "Not found"
        }
        return await AXInspectorTool.getElementValue(element: element) ?? "nil"
    }

    // MARK: Input Simulation
    router.register(name: "ui_click") { args in
        let a = try decode(args, as: ClickArgs.self)
        switch a.button?.lowercased() {
        case "right":
            try CGEventTool.rightClick(x: a.x, y: a.y)
        case "center":
            try CGEventTool.click(x: a.x, y: a.y, button: .center)
        default:
            try CGEventTool.click(x: a.x, y: a.y)
        }
        return "Clicked"
    }
    router.register(name: "ui_double_click") { args in
        let a = try decode(args, as: PointArgs.self)
        try CGEventTool.doubleClick(x: a.x, y: a.y)
        return "Double-clicked"
    }
    router.register(name: "ui_right_click") { args in
        let a = try decode(args, as: PointArgs.self)
        try CGEventTool.rightClick(x: a.x, y: a.y)
        return "Right-clicked"
    }
    router.register(name: "ui_drag") { args in
        let a = try decode(args, as: DragArgs.self)
        try CGEventTool.drag(fromX: a.fromX, fromY: a.fromY, toX: a.toX, toY: a.toY)
        return "Dragged"
    }
    router.register(name: "ui_type") { args in
        let a = try decode(args, as: TextArgs.self)
        try CGEventTool.typeText(a.text)
        return "Typed"
    }
    router.register(name: "ui_key") { args in
        let a = try decode(args, as: KeyArgs.self)
        try CGEventTool.pressKey(a.key)
        return "Key pressed"
    }
    router.register(name: "ui_scroll") { args in
        let a = try decode(args, as: ScrollArgs.self)
        try CGEventTool.scroll(x: a.x, y: a.y, deltaX: a.deltaX, deltaY: a.deltaY)
        return "Scrolled"
    }

    // MARK: Vision
    router.register(name: "ui_screenshot") { args in
        let a = try decode(args, as: ScreenshotArgs.self)
        let quality = a.quality ?? 0.85
        let data: Data
        if let bundleId = a.bundleId {
            data = try await ScreenCaptureTool.captureWindow(bundleID: bundleId, quality: quality)
        } else {
            data = try await ScreenCaptureTool.captureDisplay(quality: quality)
        }
        // Persist the capture so vision_query can retrieve it. The returned path
        // is the image id callers pass back to vision_query.
        let path = NSTemporaryDirectory() + "merlin-screenshot-\(UUID().uuidString).jpg"
        try data.write(to: URL(fileURLWithPath: path))
        return "Screenshot captured (\(data.count) bytes). image id: \(path)"
    }
    router.register(name: "vision_query") { args in
        let a = try decode(args, as: VisionQueryArgs.self)
        guard let provider = visionProvider() else {
            return "vision_query error: no vision model is configured (set the vision slot)"
        }
        guard let jpeg = loadImageAsJPEG(a.imageId) else {
            return "vision_query error: could not load image '\(a.imageId)' — pass a "
                + "screenshot id from ui_screenshot or an image file path"
        }
        return try await VisionQueryTool.query(
            imageData: jpeg, prompt: a.prompt, provider: provider)
    }
}

// MARK: - Decode helpers

private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
    guard let data = json.data(using: .utf8) else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid UTF-8"))
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: data)
}

struct BuiltInToolScope {
    var path: String
    var warning: String?

    func prefixed(_ output: String) -> String {
        guard let warning else { return output }
        return warning + "\n" + output
    }

    func mergingWarning(with other: BuiltInToolScope) -> BuiltInToolScope {
        let merged = [warning, other.warning].compactMap { $0 }.joined(separator: "\n")
        return BuiltInToolScope(path: path, warning: merged.isEmpty ? nil : merged)
    }

    static func resolvePath(_ rawPath: String?, defaultProjectPath: String?) -> BuiltInToolScope {
        let projectRoot = normalizedRoot(defaultProjectPath)
        let trimmed = rawPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let effectiveRaw = trimmed.isEmpty ? "." : trimmed
        let url: URL
        if effectiveRaw.hasPrefix("/") {
            url = URL(fileURLWithPath: effectiveRaw)
        } else if let projectRoot {
            url = URL(fileURLWithPath: projectRoot, isDirectory: true)
                .appendingPathComponent(effectiveRaw)
        } else {
            url = URL(fileURLWithPath: effectiveRaw)
        }

        let path = url.standardizedFileURL.path
        if let projectRoot,
           effectiveRaw.hasPrefix("/"),
           let fallback = projectRequirementsFallback(
               requestedPath: path,
               projectRoot: projectRoot
           ) {
            return fallback
        }
        return BuiltInToolScope(path: path, warning: outsideProjectWarning(path: path, projectRoot: projectRoot))
    }

    static func resolveCWD(_ rawCWD: String?, defaultProjectPath: String?) -> BuiltInToolScope {
        let projectRoot = normalizedRoot(defaultProjectPath)
        let trimmed = rawCWD?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            return BuiltInToolScope(path: projectRoot ?? ".", warning: nil)
        }
        return resolvePath(trimmed, defaultProjectPath: defaultProjectPath)
    }

    private static func normalizedRoot(_ defaultProjectPath: String?) -> String? {
        guard let defaultProjectPath,
              !defaultProjectPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return URL(fileURLWithPath: defaultProjectPath, isDirectory: true).standardizedFileURL.path
    }

    private static func outsideProjectWarning(path: String, projectRoot: String?) -> String? {
        guard let projectRoot else { return nil }
        guard path == projectRoot || path.hasPrefix(projectRoot + "/") else {
            return "Warning: requested path is outside current project root. Current project root: \(projectRoot). Requested path: \(path)."
        }
        return nil
    }

    private static func projectRequirementsFallback(
        requestedPath: String,
        projectRoot: String
    ) -> BuiltInToolScope? {
        let requestedURL = URL(fileURLWithPath: requestedPath)
        let fileName = requestedURL.lastPathComponent.lowercased()
        guard ["spec.md", "requirements.md", "requirements.txt"].contains(fileName),
              requestedPath != projectRoot + "/" + requestedURL.lastPathComponent,
              !FileManager.default.fileExists(atPath: requestedPath)
        else { return nil }

        let candidateURL = URL(fileURLWithPath: projectRoot, isDirectory: true)
            .appendingPathComponent(requestedURL.lastPathComponent)
            .standardizedFileURL
        guard FileManager.default.fileExists(atPath: candidateURL.path) else { return nil }

        return BuiltInToolScope(
            path: candidateURL.path,
            warning: "Warning: requested absolute requirements/spec path did not exist and was corrected to current project root. Current project root: \(projectRoot). Requested path: \(requestedPath). Corrected path: \(candidateURL.path)."
        )
    }
}

private struct PathArgs: Decodable { var path: String? }
private struct WriteFileArgs: Decodable { var path: String?; var content: String }
private struct ListDirectoryArgs: Decodable { var path: String?; var recursive: Bool? }
private struct MoveFileArgs: Decodable { var src: String?; var dst: String? }
private struct SearchFilesArgs: Decodable { var path: String?; var pattern: String; var contentPattern: String? }
private struct RunShellArgs: Decodable {
    var command: String
    var cwd: String?
    var timeoutSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case command
        case cwd
        case timeoutSeconds
        case timeoutSecondsSnake = "timeout_seconds"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        command = try container.decode(String.self, forKey: .command)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds)
            ?? container.decodeIfPresent(Int.self, forKey: .timeoutSecondsSnake)
    }
}
private struct LaunchAppArgs: Decodable { var bundleId: String; var arguments: [String]? }
private struct BundleIDArgs: Decodable { var bundleId: String }
private struct CwdArgs: Decodable { var cwd: String? }
private struct XcodeBuildArgs: Decodable { var scheme: String; var configuration: String; var destination: String? }
private struct XcodeTestArgs: Decodable { var scheme: String; var testId: String? }
private struct XcodeOpenFileArgs: Decodable { var path: String; var line: Int }
private struct UdidArgs: Decodable { var udid: String }
private struct SimulatorInstallArgs: Decodable { var udid: String; var appPath: String }
private struct FindElementArgs: Decodable { var bundleId: String; var role: String?; var label: String?; var value: String? }
private struct ElementValueArgs: Decodable { var bundleId: String; var label: String }
private struct ClickArgs: Decodable { var x: Double; var y: Double; var button: String? }
private struct PointArgs: Decodable { var x: Double; var y: Double }
private struct DragArgs: Decodable { var fromX: Double; var fromY: Double; var toX: Double; var toY: Double }
private struct TextArgs: Decodable { var text: String }
private struct KeyArgs: Decodable { var key: String }
private struct ScrollArgs: Decodable { var x: Double; var y: Double; var deltaX: Double; var deltaY: Double }
private struct ScreenshotArgs: Decodable { var bundleId: String?; var quality: Double? }
private struct VisionQueryArgs: Decodable { var imageId: String; var prompt: String }
private struct ProjectPathArgs: Decodable { var projectPath: String? }
