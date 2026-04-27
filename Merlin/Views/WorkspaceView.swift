import SwiftUI

struct WorkspaceView: View {
    let projectRef: ProjectRef

    var body: some View {
        Text("Loading \(projectRef.displayName)…")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
