import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        // Bring the workspace window to front if the user clicks the Dock icon
        // while the app is already running with no visible windows.
        if !flag {
            NSApp.windows.first { $0.identifier?.rawValue == "workspace" }?
                .makeKeyAndOrderFront(nil)
        }
        return true
    }
}

@main
struct MerlinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recents = RecentProjectsStore()
    @StateObject private var scheduler = SchedulerEngine()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup("Merlin", id: "workspace") {
            WorkspaceView()
                .environmentObject(recents)
                .frame(minWidth: 900, minHeight: 600)
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
