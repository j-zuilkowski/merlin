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
        // A freshly built app (the common case right after xcode_build) is not yet
        // registered with Launch Services, so urlForApplication returns nil — fall
        // back to locating the .app in Xcode's DerivedData by bundle id.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? findBuiltApp(bundleID: bundleID) else {
            throw AppControlError.applicationNotFound(bundleID)
        }

        // @unchecked Sendable rationale: function-local; written on the launch-completion
        // thread, read on this thread after `semaphore.wait()` (happens-after barrier).
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

    /// Locates a `.app` by bundle id under Xcode's DerivedData build products —
    /// the build output of `xcode_build`, before Launch Services knows the bundle.
    /// Returns the most recently built match.
    private static func findBuiltApp(bundleID: String) -> URL? {
        let fm = FileManager.default
        let derivedData = fm.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        guard let projects = try? fm.contentsOfDirectory(
            at: derivedData, includingPropertiesForKeys: nil) else { return nil }

        var best: (url: URL, modified: Date)?
        for project in projects {
            let products = project.appendingPathComponent("Build/Products", isDirectory: true)
            guard let configs = try? fm.contentsOfDirectory(
                at: products, includingPropertiesForKeys: nil) else { continue }
            for config in configs {
                guard let apps = try? fm.contentsOfDirectory(
                    at: config, includingPropertiesForKeys: [.contentModificationDateKey])
                else { continue }
                for app in apps where app.pathExtension == "app" {
                    let infoPlist = app.appendingPathComponent("Contents/Info.plist")
                    guard let plist = NSDictionary(contentsOf: infoPlist),
                          plist["CFBundleIdentifier"] as? String == bundleID else { continue }
                    let modified = (try? app.resourceValues(
                        forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    if best == nil || modified > best!.modified {
                        best = (app, modified)
                    }
                }
            }
        }
        return best?.url
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
