import SwiftUI
import AppKit

@MainActor
final class WorkspaceWindowRecoveryManager {
    static let shared = WorkspaceWindowRecoveryManager()

    private let recents = RecentProjectsStore()
    private let scheduler = SchedulerEngine()
    private let toolRequirements = ToolRequirementCoordinator.shared
    private var window: NSWindow?

    func openFallbackWindowIfNeeded(force: Bool = false) {
        if Self.hasUsableWorkspaceWindow(in: NSApp.windows) {
            return
        }

        if !force,
           let repaired = Self.repairFirstWorkspaceWindowIfNeeded(in: NSApp.windows) {
            Self.present(repaired)
            return
        }

        if let window {
            Self.ensureUsableWorkspaceFrame(window)
            Self.present(window)
            return
        }

        let view = WorkspaceView()
            .environmentObject(recents)
            .environmentObject(scheduler)
            .frame(minWidth: 900, minHeight: 600)
            .sheet(item: Binding(
                get: { self.toolRequirements.pending },
                set: { _ in }
            )) { requirement in
                ToolRequirementSheet(
                    requirement: requirement,
                    coordinator: self.toolRequirements
                )
            }

        let window = NSWindow(
            contentRect: NSRect(x: 200, y: 160, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.identifier = NSUserInterfaceItemIdentifier("workspace")
        window.title = "Merlin"
        window.contentView = NSHostingView(rootView: view)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.moveToActiveSpace)
        self.window = window

        window.center()
        Self.present(window)
    }

    static func hasUsableWorkspaceWindow(in windows: [NSWindow]) -> Bool {
        windows.contains { window in
            window.isVisible
                && !window.isMiniaturized
                && window.canBecomeKey
                && window.styleMask.contains(.titled)
                && window.frame.width >= 900
                && window.frame.height >= 600
        }
    }

    @discardableResult
    static func repairFirstWorkspaceWindowIfNeeded(in windows: [NSWindow]) -> NSWindow? {
        guard let window = windows.first(where: { candidate in
            candidate.canBecomeKey && candidate.styleMask.contains(.titled)
        }) else {
            return nil
        }
        ensureUsableWorkspaceFrame(window)
        return window
    }

    static func ensureUsableWorkspaceFrame(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        guard window.frame.width < 900 || window.frame.height < 600 else {
            return
        }

        let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        window.setFrame(usableWorkspaceFrame(in: visibleFrame), display: true)
    }

    static func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.regular)
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [
            .activateAllWindows,
            .activateIgnoringOtherApps
        ])
    }

    static func usableWorkspaceFrame(in visibleFrame: NSRect) -> NSRect {
        let size = NSSize(width: 1200, height: 800)
        let origin = NSPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.midY - size.height / 2
        )
        return NSRect(origin: origin, size: size)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        scheduleWorkspaceWindowRecovery()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func application(_ application: NSApplication,
                     shouldSaveSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func application(_ application: NSApplication,
                     shouldRestoreSecureApplicationState coder: NSCoder) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        // Bring the workspace window to front if the user clicks the Dock icon
        // while the app is already running with no visible windows.
        if !flag {
            scheduleWorkspaceWindowRecovery()
        }
        return true
    }

    @MainActor
    private func scheduleWorkspaceWindowRecovery() {
        let allowFallback = Self.shouldAllowFallbackWindowRecovery(
            arguments: ProcessInfo.processInfo.arguments
        )
        if allowFallback {
            WorkspaceWindowRecoveryManager.shared.openFallbackWindowIfNeeded(force: true)
        }
        for delay in [0.0, 0.25, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.orderFrontWorkspaceWindowIfNeeded()
            }
        }
        guard allowFallback else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            WorkspaceWindowRecoveryManager.shared.openFallbackWindowIfNeeded(force: allowFallback)
        }
    }

    static func shouldAllowFallbackWindowRecovery(arguments: [String]) -> Bool {
        arguments.contains("--open-project") || arguments.contains("--open-test-project")
    }

    @MainActor
    static func orderFrontWorkspaceWindowIfNeeded(
        windows: [NSWindow] = NSApp.windows,
        hasVisibleWindows: Bool = NSApp.windows.contains(where: \.isVisible)
    ) {
        if hasVisibleWindows,
           WorkspaceWindowRecoveryManager.hasUsableWorkspaceWindow(in: windows) {
            return
        }
        guard let window = windows.first(where: { candidate in
            candidate.canBecomeKey && candidate.styleMask.contains(.titled)
        }) else {
            return
        }

        WorkspaceWindowRecoveryManager.ensureUsableWorkspaceFrame(window)
        WorkspaceWindowRecoveryManager.present(window)
    }
}

@main
struct MerlinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recents = RecentProjectsStore()
    @StateObject private var scheduler = SchedulerEngine()
    @StateObject private var settings = AppSettings.shared
    @StateObject private var toolRequirements = ToolRequirementCoordinator.shared

    init() {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        Self.scheduleWorkspaceRecoveryFromSwiftUIEntry(
            arguments: ProcessInfo.processInfo.arguments
        )
    }

    private static func scheduleWorkspaceRecoveryFromSwiftUIEntry(arguments: [String]) {
        let allowFallback = AppDelegate.shouldAllowFallbackWindowRecovery(arguments: arguments)

        for delay in [0.0, 0.25, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                AppDelegate.orderFrontWorkspaceWindowIfNeeded()
            }
        }
        guard allowFallback else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            WorkspaceWindowRecoveryManager.shared.openFallbackWindowIfNeeded(force: allowFallback)
        }
    }

    var body: some Scene {
        WindowGroup("Merlin", id: "workspace") {
            WorkspaceView()
                .environmentObject(recents)
                .frame(minWidth: 900, minHeight: 600)
                .sheet(item: $toolRequirements.pending) { requirement in
                    ToolRequirementSheet(
                        requirement: requirement,
                        coordinator: toolRequirements
                    )
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands { MerlinCommands() }
        .defaultSize(width: 1200, height: 800)

        Settings {
            SettingsWindowView()
                .environmentObject(scheduler)
        }
        .windowResizability(.contentMinSize)
    }
}
