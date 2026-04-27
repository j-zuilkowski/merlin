import SwiftUI

private struct IsEngineRunningKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct ActiveProviderIDKey: FocusedValueKey {
    typealias Value = Binding<String>
}

extension FocusedValues {
    var isEngineRunning: Binding<Bool>? {
        get { self[IsEngineRunningKey.self] }
        set { self[IsEngineRunningKey.self] = newValue }
    }

    var activeProviderID: Binding<String>? {
        get { self[ActiveProviderIDKey.self] }
        set { self[ActiveProviderIDKey.self] = newValue }
    }
}
