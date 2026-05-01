import Foundation

@MainActor
func registerAllTools(router: ToolRouter) {
    // MARK: File System
    router.register(name: "read_file") { args in
        let a = try decode(args, as: PathArgs.self)
        return try await FileSystemTools.readFile(path: a.path)
    }
    router.register(name: "write_file") { args in
        let a = try decode(args, as: WriteFileArgs.self)
        try await FileSystemTools.writeFile(path: a.path, content: a.content)
        return "Written"
    }
    router.register(name: "create_file") { args in
        let a = try decode(args, as: PathArgs.self)
        try await FileSystemTools.createFile(path: a.path)
        return "Created"
    }
    router.register(name: "delete_file") { args in
        let a = try decode(args, as: PathArgs.self)
        try await FileSystemTools.deleteFile(path: a.path)
        return "Deleted"
    }
    router.register(name: "list_directory") { args in
        let a = try decode(args, as: ListDirectoryArgs.self)
        return try await FileSystemTools.listDirectory(path: a.path, recursive: a.recursive ?? false)
    }
    router.register(name: "move_file") { args in
        let a = try decode(args, as: MoveFileArgs.self)
        try await FileSystemTools.moveFile(src: a.src, dst: a.dst)
        return "Moved"
    }
    router.register(name: "search_files") { args in
        let a = try decode(args, as: SearchFilesArgs.self)
        return try await FileSystemTools.searchFiles(path: a.path, pattern: a.pattern, contentPattern: a.contentPattern)
    }

    // MARK: Shell
    router.register(name: "run_shell") { args in
        let a = try decode(args, as: RunShellArgs.self)
        let result = try await ShellTool.run(
            command: a.command,
            cwd: a.cwd,
            timeoutSeconds: a.timeoutSeconds ?? 120
        )
        return "exit:\(result.exitCode)\nstdout:\(result.stdout)\nstderr:\(result.stderr)"
    }
    // Alias for models trained on Claude computer-use format (e.g. DeepSeek V4 Pro)
    router.register(name: "bash") { args in
        let a = try decode(args, as: RunShellArgs.self)
        let result = try await ShellTool.run(
            command: a.command,
            cwd: a.cwd,
            timeoutSeconds: a.timeoutSeconds ?? 120
        )
        return "exit:\(result.exitCode)\nstdout:\(result.stdout)\nstderr:\(result.stderr)"
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
    router.register(name: "tool_discover") { _ in
        let tools = await ToolDiscovery.scan()
        return tools.map { "\($0.name): \($0.path)" }.joined(separator: "\n")
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
        let summary = try XcodeTools.parseXcresult(path: a.path)
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
        return "JPEG: \(data.count) bytes"
    }
    router.register(name: "vision_query") { args in
        _ = try decode(args, as: VisionQueryArgs.self)
        return "vision_query: use ui_screenshot first to capture, then this tool queries it"
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

private struct PathArgs: Decodable { var path: String }
private struct WriteFileArgs: Decodable { var path: String; var content: String }
private struct ListDirectoryArgs: Decodable { var path: String; var recursive: Bool? }
private struct MoveFileArgs: Decodable { var src: String; var dst: String }
private struct SearchFilesArgs: Decodable { var path: String; var pattern: String; var contentPattern: String? }
private struct RunShellArgs: Decodable { var command: String; var cwd: String?; var timeoutSeconds: Int? }
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
