import SwiftUI

@main
struct MerlinApp: App {
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
