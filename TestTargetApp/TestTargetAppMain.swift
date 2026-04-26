import SwiftUI

@main
struct TestTargetApp: App {
    var body: some Scene {
        WindowGroup("TestTargetApp") {
            ContentView()
                .frame(width: 600, height: 500)
        }
        .windowResizability(.contentSize)
    }
}
