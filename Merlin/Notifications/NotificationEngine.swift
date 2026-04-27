import Foundation
import UserNotifications

actor NotificationEngine {
    func requestAuthorization() async {
        guard isNotificationEnvironmentAvailable else {
            return
        }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    func post(title: String, body: String, identifier: String) async {
        guard isNotificationEnvironmentAvailable else {
            return
        }
        guard await MainActor.run(body: { AppSettings.shared.notificationsEnabled }) else {
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    func notifyTaskComplete(sessionLabel: String) async {
        await post(
            title: "Task complete",
            body: "\(sessionLabel) finished.",
            identifier: "task-complete-\(UUID().uuidString)"
        )
    }

    func notifyApprovalNeeded(toolName: String) async {
        await post(
            title: "Approval needed",
            body: "\(toolName) is waiting for your approval.",
            identifier: "approval-\(UUID().uuidString)"
        )
    }

    private var isNotificationEnvironmentAvailable: Bool {
        ProcessInfo.processInfo.processName != "xctest" &&
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }
}
