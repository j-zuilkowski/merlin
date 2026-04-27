import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwakeManager: ObservableObject {
    static let shared = KeepAwakeManager()

    private var assertionID: IOPMAssertionID = 0
    private var isHeld = false

    func apply(_ keepAwake: Bool) {
        if keepAwake {
            enable()
        } else {
            disable()
        }
    }

    private func enable() {
        guard !isHeld else { return }
        let name = "Merlin long session" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            name,
            &assertionID
        )
        if result == kIOReturnSuccess {
            isHeld = true
        }
    }

    private func disable() {
        guard isHeld else { return }
        IOPMAssertionRelease(assertionID)
        isHeld = false
    }
}
