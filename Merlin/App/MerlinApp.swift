import SwiftUI

@main
struct MerlinApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            if appState.showFirstLaunchSetup {
                FirstLaunchSetupView()
                    .environmentObject(appState)
            } else {
                ContentView()
                    .environmentObject(appState)
                    .frame(minWidth: 900, minHeight: 600)
            }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
