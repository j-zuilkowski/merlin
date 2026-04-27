import SwiftUI

@main
struct MerlinApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.showFirstLaunchSetup {
                FirstLaunchSetupView()
                    .environmentObject(appState)
                    .environmentObject(appState.registry)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .environmentObject(appState.registry)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            MerlinCommands()
        }

        Settings {
            ProviderSettingsView()
                .environmentObject(appState.registry)
        }
    }
}
