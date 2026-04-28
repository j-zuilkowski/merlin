import SwiftUI
import AppKit

// Closes the project picker when workspace windows are already being restored
// from the previous session. Without this, state restoration reopens both the
// picker and every workspace window simultaneously.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Give SwiftUI a moment to finish restoring all windows, then check.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let hasWorkspace = NSApp.windows.contains { window in
                window.isVisible
                    && window.styleMask.contains(.titled)
                    && window.title != "Merlin"      // picker title
                    && window.title != "Settings"
                    && !window.title.isEmpty
            }
            if hasWorkspace {
                NSApp.windows
                    .filter { $0.title == "Merlin" }
                    .forEach { $0.orderOut(nil) }
            }
        }
    }
}

@main
struct MerlinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var recents = RecentProjectsStore()
    @StateObject private var scheduler = SchedulerEngine()
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        // Launch picker - shown when no workspace windows are open
        WindowGroup("Merlin", id: "picker") {
            ProjectPickerView()
                .environmentObject(recents)
                .preferredColorScheme(settings.appearance.theme.colorScheme)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 500, height: 380)

        // Per-project workspace window
        WindowGroup(for: ProjectRef.self) { $ref in
            if let ref {
                WorkspaceView(projectRef: ref)
                    .environmentObject(recents)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands { MerlinCommands() }

        Settings {
            SettingsWindowView()
                .environmentObject(scheduler)
        }
        .windowResizability(.contentMinSize)
    }
}
