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
        ragSearch, ragListBooks,
        .spawnAgent,
    ]

    // File System
    static let readFile = ToolDefinition(function: .init(
        name: "read_file",
        description: "Read file contents with line numbers",
        parameters: JSONSchema(
            type: "object",
            properties: ["path": JSONSchema(type: "string", description: "Absolute path")],
            required: ["path"]
        )
    ))

    static let writeFile = ToolDefinition(function: .init(
        name: "write_file",
        description: "Write content to a file, creating intermediate directories",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "path": JSONSchema(type: "string", description: "Absolute path"),
                "content": JSONSchema(type: "string", description: "File content"),
            ],
            required: ["path", "content"]
        )
    ))

    static let createFile = ToolDefinition(function: .init(
        name: "create_file",
        description: "Create an empty file",
        parameters: JSONSchema(
            type: "object",
            properties: ["path": JSONSchema(type: "string", description: "Absolute path")],
            required: ["path"]
        )
    ))

    static let deleteFile = ToolDefinition(function: .init(
        name: "delete_file",
        description: "Delete a file",
        parameters: JSONSchema(
            type: "object",
            properties: ["path": JSONSchema(type: "string", description: "Absolute path")],
            required: ["path"]
        )
    ))

    static let listDirectory = ToolDefinition(function: .init(
        name: "list_directory",
        description: "List directory contents",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "path": JSONSchema(type: "string", description: "Absolute path"),
                "recursive": JSONSchema(type: "boolean", description: "List recursively"),
            ],
            required: ["path"]
        )
    ))

    static let moveFile = ToolDefinition(function: .init(
        name: "move_file",
        description: "Move or rename a file",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "src": JSONSchema(type: "string", description: "Source path"),
                "dst": JSONSchema(type: "string", description: "Destination path"),
            ],
            required: ["src", "dst"]
        )
    ))

    static let searchFiles = ToolDefinition(function: .init(
        name: "search_files",
        description: "Search for files by name glob and optional content pattern",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "path": JSONSchema(type: "string", description: "Directory to search"),
                "pattern": JSONSchema(type: "string", description: "Glob pattern e.g. *.swift"),
                "content_pattern": JSONSchema(type: "string", description: "Optional grep string"),
            ],
            required: ["path", "pattern"]
        )
    ))

    // Shell
    static let runShell = ToolDefinition(function: .init(
        name: "run_shell",
        description: "Run a shell command in /bin/zsh",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "command": JSONSchema(type: "string", description: "Shell command"),
                "cwd": JSONSchema(type: "string", description: "Working directory"),
                "timeout_seconds": JSONSchema(type: "integer", description: "Timeout (default 120)"),
            ],
            required: ["command"]
        )
    ))

    // App Control
    static let appLaunch = ToolDefinition(function: .init(
        name: "app_launch",
        description: "Launch a macOS application by bundle ID",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "bundle_id": JSONSchema(type: "string", description: "Bundle identifier"),
                "arguments": JSONSchema(type: "array", items: JSONSchema(type: "string"), description: "Launch arguments"),
            ],
            required: ["bundle_id"]
        )
    ))

    static let appListRunning = ToolDefinition(function: .init(
        name: "app_list_running",
        description: "List all running applications",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))

    static let appQuit = ToolDefinition(function: .init(
        name: "app_quit",
        description: "Quit a running application by bundle ID",
        parameters: JSONSchema(
            type: "object",
            properties: ["bundle_id": JSONSchema(type: "string", description: "Bundle identifier")],
            required: ["bundle_id"]
        )
    ))

    static let appFocus = ToolDefinition(function: .init(
        name: "app_focus",
        description: "Bring an application to the foreground",
        parameters: JSONSchema(
            type: "object",
            properties: ["bundle_id": JSONSchema(type: "string", description: "Bundle identifier")],
            required: ["bundle_id"]
        )
    ))

    // Discovery
    static let toolDiscover = ToolDefinition(function: .init(
        name: "tool_discover",
        description: "Discover CLI tools available on PATH",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))

    // Xcode
    static let xcodeBuild = ToolDefinition(function: .init(
        name: "xcode_build",
        description: "Build an Xcode scheme",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "scheme": JSONSchema(type: "string", description: "Scheme name"),
                "configuration": JSONSchema(type: "string", description: "Debug or Release"),
                "destination": JSONSchema(type: "string", description: "xcodebuild destination string"),
            ],
            required: ["scheme", "configuration"]
        )
    ))

    static let xcodeTest = ToolDefinition(function: .init(
        name: "xcode_test",
        description: "Run Xcode tests for a scheme",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "scheme": JSONSchema(type: "string", description: "Scheme name"),
                "test_id": JSONSchema(type: "string", description: "Optional test filter"),
            ],
            required: ["scheme"]
        )
    ))

    static let xcodeClean = ToolDefinition(function: .init(
        name: "xcode_clean",
        description: "Clean the Xcode build",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))

    static let xcodeDerivedDataClean = ToolDefinition(function: .init(
        name: "xcode_derived_data_clean",
        description: "Delete DerivedData directory",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))

    static let xcodeOpenFile = ToolDefinition(function: .init(
        name: "xcode_open_file",
        description: "Open a file at a specific line in Xcode",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "path": JSONSchema(type: "string", description: "Absolute file path"),
                "line": JSONSchema(type: "integer", description: "Line number"),
            ],
            required: ["path", "line"]
        )
    ))

    static let xcodeXcresultParse = ToolDefinition(function: .init(
        name: "xcode_xcresult_parse",
        description: "Parse an .xcresult bundle and return test failures",
        parameters: JSONSchema(
            type: "object",
            properties: ["path": JSONSchema(type: "string", description: "Path to .xcresult")],
            required: ["path"]
        )
    ))

    static let xcodeSimulatorList = ToolDefinition(function: .init(
        name: "xcode_simulator_list",
        description: "List available simulators as JSON",
        parameters: JSONSchema(type: "object", properties: [:], required: [])
    ))

    static let xcodeSimulatorBoot = ToolDefinition(function: .init(
        name: "xcode_simulator_boot",
        description: "Boot a simulator by UDID",
        parameters: JSONSchema(
            type: "object",
            properties: ["udid": JSONSchema(type: "string", description: "Simulator UDID")],
            required: ["udid"]
        )
    ))

    static let xcodeSimulatorScreenshot = ToolDefinition(function: .init(
        name: "xcode_simulator_screenshot",
        description: "Capture a screenshot from a booted simulator",
        parameters: JSONSchema(
            type: "object",
            properties: ["udid": JSONSchema(type: "string", description: "Simulator UDID")],
            required: ["udid"]
        )
    ))

    static let xcodeSimulatorInstall = ToolDefinition(function: .init(
        name: "xcode_simulator_install",
        description: "Install an app on a simulator",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "udid": JSONSchema(type: "string", description: "Simulator UDID"),
                "app_path": JSONSchema(type: "string", description: "Path to .app bundle"),
            ],
            required: ["udid", "app_path"]
        )
    ))

    static let xcodeSpmResolve = ToolDefinition(function: .init(
        name: "xcode_spm_resolve",
        description: "Run swift package resolve",
        parameters: JSONSchema(
            type: "object",
            properties: ["cwd": JSONSchema(type: "string", description: "Working directory")],
            required: ["cwd"]
        )
    ))

    static let xcodeSpmList = ToolDefinition(function: .init(
        name: "xcode_spm_list",
        description: "Run swift package show-dependencies",
        parameters: JSONSchema(
            type: "object",
            properties: ["cwd": JSONSchema(type: "string", description: "Working directory")],
            required: ["cwd"]
        )
    ))

    // AX / GUI Inspect
    static let uiInspect = ToolDefinition(function: .init(
        name: "ui_inspect",
        description: "Inspect the Accessibility tree of a running app",
        parameters: JSONSchema(
            type: "object",
            properties: ["bundle_id": JSONSchema(type: "string", description: "Bundle identifier")],
            required: ["bundle_id"]
        )
    ))

    static let uiFindElement = ToolDefinition(function: .init(
        name: "ui_find_element",
        description: "Find an AX element by role, label, or value",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "bundle_id": JSONSchema(type: "string", description: "Bundle identifier"),
                "role": JSONSchema(type: "string", description: "AX role e.g. AXButton"),
                "label": JSONSchema(type: "string", description: "Accessibility label"),
                "value": JSONSchema(type: "string", description: "Element value"),
            ],
            required: ["bundle_id"]
        )
    ))

    static let uiGetElementValue = ToolDefinition(function: .init(
        name: "ui_get_element_value",
        description: "Get the current value of a UI element by label",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "bundle_id": JSONSchema(type: "string", description: "Bundle identifier"),
                "label": JSONSchema(type: "string", description: "Accessibility label"),
            ],
            required: ["bundle_id", "label"]
        )
    ))

    // Input Simulation
    static let uiClick = ToolDefinition(function: .init(
        name: "ui_click",
        description: "Click at screen coordinates",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "x": JSONSchema(type: "number", description: "X coordinate"),
                "y": JSONSchema(type: "number", description: "Y coordinate"),
                "button": JSONSchema(type: "string", description: "left, right, or center"),
            ],
            required: ["x", "y"]
        )
    ))

    static let uiDoubleClick = ToolDefinition(function: .init(
        name: "ui_double_click",
        description: "Double-click at screen coordinates",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "x": JSONSchema(type: "number", description: "X coordinate"),
                "y": JSONSchema(type: "number", description: "Y coordinate"),
            ],
            required: ["x", "y"]
        )
    ))

    static let uiRightClick = ToolDefinition(function: .init(
        name: "ui_right_click",
        description: "Right-click at screen coordinates",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "x": JSONSchema(type: "number", description: "X coordinate"),
                "y": JSONSchema(type: "number", description: "Y coordinate"),
            ],
            required: ["x", "y"]
        )
    ))

    static let uiDrag = ToolDefinition(function: .init(
        name: "ui_drag",
        description: "Drag from one screen position to another",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "from_x": JSONSchema(type: "number", description: "Start X"),
                "from_y": JSONSchema(type: "number", description: "Start Y"),
                "to_x": JSONSchema(type: "number", description: "End X"),
                "to_y": JSONSchema(type: "number", description: "End Y"),
            ],
            required: ["from_x", "from_y", "to_x", "to_y"]
        )
    ))

    static let uiType = ToolDefinition(function: .init(
        name: "ui_type",
        description: "Type text at the current cursor position",
        parameters: JSONSchema(
            type: "object",
            properties: ["text": JSONSchema(type: "string", description: "Text to type")],
            required: ["text"]
        )
    ))

    static let uiKey = ToolDefinition(function: .init(
        name: "ui_key",
        description: "Press a key or key combination e.g. cmd+s, return, escape",
        parameters: JSONSchema(
            type: "object",
            properties: ["key": JSONSchema(type: "string", description: "Key combo string")],
            required: ["key"]
        )
    ))

    static let uiScroll = ToolDefinition(function: .init(
        name: "ui_scroll",
        description: "Scroll at screen coordinates",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "x": JSONSchema(type: "number", description: "X coordinate"),
                "y": JSONSchema(type: "number", description: "Y coordinate"),
                "delta_x": JSONSchema(type: "number", description: "Horizontal scroll delta"),
                "delta_y": JSONSchema(type: "number", description: "Vertical scroll delta"),
            ],
            required: ["x", "y", "delta_x", "delta_y"]
        )
    ))

    // Vision
    static let uiScreenshot = ToolDefinition(function: .init(
        name: "ui_screenshot",
        description: "Capture a screenshot of the display or a specific app window",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "bundle_id": JSONSchema(type: "string", description: "Optional: capture specific app window"),
                "quality": JSONSchema(type: "number", description: "JPEG quality 0.0-1.0 (default 0.85)"),
            ],
            required: []
        )
    ))

    static let visionQuery = ToolDefinition(function: .init(
        name: "vision_query",
        description: "Query the vision model about the last captured screenshot",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "image_id": JSONSchema(type: "string", description: "ID from ui_screenshot result"),
                "prompt": JSONSchema(type: "string", description: "Question about the screenshot"),
            ],
            required: ["image_id", "prompt"]
        )
    ))

    // RAG
    static let ragSearch = ToolDefinition(function: .init(
        name: "rag_search",
        description: "Search your personal library for relevant passages using semantic and keyword search. Use when you need to look something up in your books or memory. Returns ranked text chunks with source and heading.",
        parameters: JSONSchema(
            type: "object",
            properties: [
                "query": JSONSchema(
                    type: "string",
                    description: "The search query"
                ),
                "source": JSONSchema(
                    type: "string",
                    description: #"Scope of search: "books" (default), "memory", or "all"."#,
                    enumValues: ["books", "memory", "all"]
                ),
                "book_ids": JSONSchema(
                    type: "array",
                    items: JSONSchema(type: "string"),
                    description: "Optional book IDs to scope the search. Omit to search all books."
                ),
                "project_path": JSONSchema(
                    type: "string",
                    description: "Optional project directory to scope memory results."
                ),
                "limit": JSONSchema(
                    type: "integer",
                    description: "Number of passages to return (1-20). Default: 10."
                ),
                "rerank": JSONSchema(
                    type: "boolean",
                    description: "LLM reranking for higher quality at the cost of latency (~8s). Default: false."
                ),
            ],
            required: ["query"]
        )
    ))

    static let ragListBooks = ToolDefinition(function: .init(
        name: "rag_list_books",
        description: "List all books in your personal library with their IDs. Use before rag_search when you want to scope results to a specific book.",
        parameters: JSONSchema(
            type: "object",
            properties: [:],
            required: []
        )
    ))
}
