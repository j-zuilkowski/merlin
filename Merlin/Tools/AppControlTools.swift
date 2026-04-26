import AppKit
import Foundation

struct RunningAppInfo: Codable, Sendable {
    var bundleID: String
    var name: String
    var pid: Int
}

enum AppControlError: Error, Sendable {
    case applicationNotFound(String)
    case launchFailed(String)
    case quitFailed(String)
    case focusFailed(String)
}

enum AppControlTools {
    static func launch(bundleID: String, arguments: [String] = []) throws {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw AppControlError.applicationNotFound(bundleID)
        }

        final class LaunchState: @unchecked Sendable {
            var error: Error?
        }

        let state = LaunchState()
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached(priority: .userInitiated) {
            do {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.arguments = arguments
                try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } catch {
                state.error = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = state.error {
            throw AppControlError.launchFailed(String(describing: error))
        }
    }

    static func listRunning() -> [RunningAppInfo] {
        var apps: [RunningAppInfo] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let bundleID = app.bundleIdentifier else { continue }
            apps.append(RunningAppInfo(bundleID: bundleID, name: app.localizedName ?? bundleID, pid: Int(app.processIdentifier)))
        }
        return apps.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    static func quit(bundleID: String) throws {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw AppControlError.applicationNotFound(bundleID)
        }

        guard app.terminate() else {
            throw AppControlError.quitFailed(bundleID)
        }
    }

    static func focus(bundleID: String) throws {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            throw AppControlError.applicationNotFound(bundleID)
        }

        _ = app.activate(options: [.activateAllWindows])
    }
}
