import SwiftUI

private struct IsEngineRunningKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

extension FocusedValues {
    var isEngineRunning: Binding<Bool>? {
        get { self[IsEngineRunningKey.self] }
        set { self[IsEngineRunningKey.self] = newValue }
    }
}
