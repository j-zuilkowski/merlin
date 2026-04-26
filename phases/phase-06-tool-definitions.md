# Phase 06 — Tool Definitions

Context: HANDOFF.md. JSONSchema and ToolDefinition types exist from phase-02b.

## Write to: Merlin/Tools/ToolDefinitions.swift

Define all tools as static `ToolDefinition` values in a `ToolDefinitions` enum.
Full tool list and descriptions are in `../architecture.md` under "Tool Registry".

Required tools (implement all):

**File System:** read_file, write_file, create_file, delete_file, list_directory, move_file, search_files
**Shell:** run_shell
**App Control:** app_launch, app_list_running, app_quit, app_focus
**Discovery:** tool_discover
**Xcode:** xcode_build, xcode_test, xcode_clean, xcode_derived_data_clean, xcode_open_file, xcode_xcresult_parse, xcode_simulator_list, xcode_simulator_boot, xcode_simulator_screenshot, xcode_simulator_install, xcode_spm_resolve, xcode_spm_list
**GUI/AX:** ui_inspect, ui_find_element, ui_get_element_value
**GUI/Input:** ui_click, ui_double_click, ui_right_click, ui_drag, ui_type, ui_key, ui_scroll
**Vision:** ui_screenshot, vision_query

```swift
enum ToolDefinitions {
    static let all: [ToolDefinition] = [
        readFile, writeFile, createFile, deleteFile,
        listDirectory, moveFile, searchFiles,
        runShell,
        appLaunch, appListRunning, appQuit, appFocus,
        toolDiscover,
        xcodeBuild, xcodeTest, xcodeClean, xcodeDerivedDataClean,
        xcodeOpenFile, xcodeXcresultParse,
        xcodeSimulatorList, xcodeSimulatorBoot,
        xcodeSimulatorScreenshot, xcodeSimulatorInstall,
        xcodeSpmResolve, xcodeSpmList,
        uiInspect, uiFindElement, uiGetElementValue,
        uiClick, uiDoubleClick, uiRightClick, uiDrag,
        uiType, uiKey, uiScroll,
        uiScreenshot, visionQuery,
    ]

    static let readFile = ToolDefinition(function: .init(
        name: "read_file",
        description: "Read file contents with line numbers",
        parameters: JSONSchema(type: "object",
            properties: ["path": JSONSchema(type: "string", description: "Absolute path")],
            required: ["path"])
    ))
    // ... implement all others following same pattern
}
```

## Acceptance
- [ ] `ToolDefinitions.all` compiles and has exactly 37 entries
- [ ] `swift build` — zero errors
- [ ] Every tool name matches the snake_case names listed above exactly
