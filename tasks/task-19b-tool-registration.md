# Phase 19b — Tool Handler Registration

## Context
Swift 5.10, macOS 14+, SwiftUI + async/await. Non-sandboxed. No third-party packages.
All value types: Sendable. OpenAI function calling format. Dynamic tool registry (ToolRegistry actor).
SWIFT_STRICT_CONCURRENCY=complete. Zero warnings, zero errors required.
Working dir: ~/Documents/localProject/merlin
All tool implementations exist (phases 07–11). ToolRouter exists (phase 15). AppState skeleton exists (phase 19).

---

## Task
Wire every tool name to its implementation inside `AppState.init`. This is the single file that connects the ToolRouter to all built-in tool functions.

## Write to: Merlin/App/ToolRegistration.swift

```swift
import Foundation

// Called from AppState.init after ToolRouter is constructed.
// Registers all built-in tool handlers.
@MainActor
func registerAllTools(router: ToolRouter) {

    // MARK: File System (7)
    router.register(name: "read_file") { args in
        let a = try decode(args, as: ["path": String.self])
        return try await FileSystemTools.readFile(path: a["path"]!)
    }
    router.register(name: "write_file") { args in
        struct A: Decodable { var path, content: String }
        let a = try decode(args, as: A.self)
        try await FileSystemTools.writeFile(path: a.path, content: a.content)
        return "Written"
    }
    router.register(name: "create_file") { args in
        let a = try decode(args, as: ["path": String.self])
        try await FileSystemTools.createFile(path: a["path"]!)
        return "Created"
    }
    router.register(name: "delete_file") { args in
        let a = try decode(args, as: ["path": String.self])
        try await FileSystemTools.deleteFile(path: a["path"]!)
        return "Deleted"
    }
    router.register(name: "list_directory") { args in
        struct A: Decodable { var path: String; var recursive: Bool? }
        let a = try decode(args, as: A.self)
        return try await FileSystemTools.listDirectory(path: a.path, recursive: a.recursive ?? false)
    }
    router.register(name: "move_file") { args in
        struct A: Decodable { var src, dst: String }
        let a = try decode(args, as: A.self)
        try await FileSystemTools.moveFile(src: a.src, dst: a.dst)
        return "Moved"
    }
    router.register(name: "search_files") { args in
        struct A: Decodable { var path, pattern: String; var content_pattern: String? }
        let a = try decode(args, as: A.self)
        return try await FileSystemTools.searchFiles(path: a.path, pattern: a.pattern, contentPattern: a.content_pattern)
    }

    // MARK: Shell (1)
    router.register(name: "run_shell") { args in
        struct A: Decodable { var command: String; var cwd: String?; var timeout_seconds: Int? }
        let a = try decode(args, as: A.self)
        let result = try await ShellTool.run(command: a.command, cwd: a.cwd,
                                             timeoutSeconds: a.timeout_seconds ?? 120)
        return "exit:\(result.exitCode)\nstdout:\(result.stdout)\nstderr:\(result.stderr)"
    }

    // MARK: App Control (4)
    router.register(name: "app_launch") { args in
        struct A: Decodable { var bundle_id: String; var arguments: [String]? }
        let a = try decode(args, as: A.self)
        try AppControlTools.launch(bundleID: a.bundle_id, arguments: a.arguments ?? [])
        return "Launched"
    }
    router.register(name: "app_list_running") { _ in
        let apps = AppControlTools.listRunning()
        return apps.map { "\($0.bundleID) (\($0.name))" }.joined(separator: "\n")
    }
    router.register(name: "app_quit") { args in
        let a = try decode(args, as: ["bundle_id": String.self])
        try AppControlTools.quit(bundleID: a["bundle_id"]!)
        return "Quit"
    }
    router.register(name: "app_focus") { args in
        let a = try decode(args, as: ["bundle_id": String.self])
        try AppControlTools.focus(bundleID: a["bundle_id"]!)
        return "Focused"
    }

    // MARK: Tool Discovery (1)
    router.register(name: "tool_discover") { _ in
        let tools = await ToolDiscovery.scan()
        return tools.map { "\($0.name): \($0.path)" }.joined(separator: "\n")
    }

    // MARK: Xcode (12)
    router.register(name: "xcode_build") { args in
        struct A: Decodable { var scheme, configuration: String; var destination: String? }
        let a = try decode(args, as: A.self)
        let r = try await XcodeTools.build(scheme: a.scheme, configuration: a.configuration, destination: a.destination)
        return r.stdout + r.stderr
    }
    router.register(name: "xcode_test") { args in
        struct A: Decodable { var scheme: String; var test_id: String? }
        let a = try decode(args, as: A.self)
        let r = try await XcodeTools.test(scheme: a.scheme, testID: a.test_id)
        return r.stdout + r.stderr
    }
    router.register(name: "xcode_clean") { _ in
        let r = try await XcodeTools.clean(); return r.stdout
    }
    router.register(name: "xcode_derived_data_clean") { _ in
        try await XcodeTools.cleanDerivedData(); return "Cleaned DerivedData"
    }
    router.register(name: "xcode_open_file") { args in
        struct A: Decodable { var path: String; var line: Int }
        let a = try decode(args, as: A.self)
        try await XcodeTools.openFile(path: a.path, line: a.line)
        return "Opened"
    }
    router.register(name: "xcode_xcresult_parse") { args in
        let a = try decode(args, as: ["path": String.self])
        let s = try XcodeTools.parseXcresult(path: a["path"]!)
        return s.testFailures?.map { "\($0.testName): \($0.message)" }.joined(separator: "\n") ?? "No failures"
    }
    router.register(name: "xcode_simulator_list") { _ in
        try await XcodeTools.simulatorList()
    }
    router.register(name: "xcode_simulator_boot") { args in
        let a = try decode(args, as: ["udid": String.self])
        try await XcodeTools.simulatorBoot(udid: a["udid"]!)
        return "Booted"
    }
    router.register(name: "xcode_simulator_screenshot") { args in
        let a = try decode(args, as: ["udid": String.self])
        let data = try await XcodeTools.simulatorScreenshot(udid: a["udid"]!)
        return "PNG: \(data.count) bytes"
    }
    router.register(name: "xcode_simulator_install") { args in
        struct A: Decodable { var udid, app_path: String }
        let a = try decode(args, as: A.self)
        try await XcodeTools.simulatorInstall(udid: a.udid, appPath: a.app_path)
        return "Installed"
    }
    router.register(name: "xcode_spm_resolve") { args in
        let a = try decode(args, as: ["cwd": String.self])
        let r = try await XcodeTools.spmResolve(cwd: a["cwd"] ?? ".")
        return r.stdout
    }
    router.register(name: "xcode_spm_list") { args in
        let a = try decode(args, as: ["cwd": String.self])
        let r = try await XcodeTools.spmList(cwd: a["cwd"] ?? ".")
        return r.stdout
    }

    // MARK: AX / GUI Inspect (3)
    router.register(name: "ui_inspect") { args in
        let a = try decode(args, as: ["bundle_id": String.self])
        let tree = await AXInspectorTool.probe(bundleID: a["bundle_id"]!)
        return tree.toJSON()
    }
    router.register(name: "ui_find_element") { args in
        struct A: Decodable { var bundle_id: String; var role, label, value: String? }
        let a = try decode(args, as: A.self)
        guard let el = await AXInspectorTool.findElement(bundleID: a.bundle_id, role: a.role, label: a.label, value: a.value)
        else { return "Not found" }
        return "frame:\(el.frame) label:\(el.label ?? "-")"
    }
    router.register(name: "ui_get_element_value") { args in
        struct A: Decodable { var bundle_id: String; var label: String }
        let a = try decode(args, as: A.self)
        if let el = await AXInspectorTool.findElement(bundleID: a.bundle_id, role: nil, label: a.label, value: nil) {
            return await AXInspectorTool.getElementValue(element: el) ?? "nil"
        }
        return "Not found"
    }

    // MARK: Input Simulation (7)
    router.register(name: "ui_click") { args in
        struct A: Decodable { var x, y: Double; var button: String? }
        let a = try decode(args, as: A.self)
        try CGEventTool.click(x: a.x, y: a.y)
        return "Clicked"
    }
    router.register(name: "ui_double_click") { args in
        struct A: Decodable { var x, y: Double }
        let a = try decode(args, as: A.self)
        try CGEventTool.doubleClick(x: a.x, y: a.y)
        return "Double-clicked"
    }
    router.register(name: "ui_right_click") { args in
        struct A: Decodable { var x, y: Double }
        let a = try decode(args, as: A.self)
        try CGEventTool.rightClick(x: a.x, y: a.y)
        return "Right-clicked"
    }
    router.register(name: "ui_drag") { args in
        struct A: Decodable { var from_x, from_y, to_x, to_y: Double }
        let a = try decode(args, as: A.self)
        try CGEventTool.drag(fromX: a.from_x, fromY: a.from_y, toX: a.to_x, toY: a.to_y)
        return "Dragged"
    }
    router.register(name: "ui_type") { args in
        let a = try decode(args, as: ["text": String.self])
        try CGEventTool.typeText(a["text"]!)
        return "Typed"
    }
    router.register(name: "ui_key") { args in
        let a = try decode(args, as: ["key": String.self])
        try CGEventTool.pressKey(a["key"]!)
        return "Key pressed"
    }
    router.register(name: "ui_scroll") { args in
        struct A: Decodable { var x, y, delta_x, delta_y: Double }
        let a = try decode(args, as: A.self)
        try CGEventTool.scroll(x: a.x, y: a.y, deltaX: a.delta_x, deltaY: a.delta_y)
        return "Scrolled"
    }

    // MARK: Vision (2)
    router.register(name: "ui_screenshot") { args in
        struct A: Decodable { var bundle_id: String?; var quality: Double? }
        let a = try decode(args, as: A.self)
        let quality = a.quality ?? 0.85
        let jpeg: Data
        if let bid = a.bundle_id {
            jpeg = try await ScreenCaptureTool.captureWindow(bundleID: bid, quality: quality)
        } else {
            jpeg = try await ScreenCaptureTool.captureDisplay(quality: quality)
        }
        return "JPEG: \(jpeg.count) bytes"
    }
    router.register(name: "vision_query") { args in
        struct A: Decodable { var image_id: String; var prompt: String }
        _ = try decode(args, as: A.self)
        return "vision_query: use ui_screenshot first to capture, then this tool queries it"
    }
}

// MARK: - Decode helpers

private func decode<T: Decodable>(_ json: String, as type: T.Type) throws -> T {
    guard let data = json.data(using: .utf8) else {
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Invalid UTF-8"))
    }
    return try JSONDecoder().decode(type, from: data)
}

private func decode(_ json: String, as schema: [String: Any.Type]) throws -> [String: String] {
    guard let data = json.data(using: .utf8),
          let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "")) }
    return obj.compactMapValues { "\($0)" }
}
```

---

## Verify

```bash
cd ~/Documents/localProject/merlin
xcodebuild -scheme MerlinTests build-for-testing -destination 'platform=macOS' 2>&1 | grep -E 'BUILD SUCCEEDED|BUILD FAILED|error:'
```

Confirm tool count matches:
```bash
grep -c 'router.register' Merlin/App/ToolRegistration.swift
```

Expected: `BUILD SUCCEEDED`. The grep count should match ToolDefinitions.all.count (one `register` call per tool; the run_shell override in AppState adds one more at runtime but is not in this file).

---

## Commit

```bash
cd ~/Documents/localProject/merlin
git add Merlin/App/ToolRegistration.swift
git commit -m "Phase 19b — registerAllTools"
```
