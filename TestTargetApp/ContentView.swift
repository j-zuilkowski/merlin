import SwiftUI

// fixtureVersion = "1.0"
// Contains exactly 8 interactive elements:
//   - Button labelled "Primary Action"       (accessibilityIdentifier: "btn-primary")
//   - Button labelled "Secondary Action"     (accessibilityIdentifier: "btn-secondary")
//   - TextField with placeholder "Enter text" (accessibilityIdentifier: "input-field")
//   - Text label showing last button pressed  (accessibilityIdentifier: "status-label")
//   - List of 5 static items: "Item 1" … "Item 5" (accessibilityIdentifier: "item-list")
//   - Toggle labelled "Enable Feature"        (accessibilityIdentifier: "feature-toggle")
//   - Button "Open Sheet"                     (accessibilityIdentifier: "btn-sheet")
//   - Sheet "Close" button                    (accessibilityIdentifier: "btn-sheet-close")

struct ContentView: View {
    @State private var statusText = "ready"
    @State private var inputText = ""
    @State private var featureEnabled = false
    @State private var showSheet = false

    let fixtureVersion = "1.0"

    var body: some View {
        VStack(spacing: 16) {
            Text(statusText)
                .accessibilityIdentifier("status-label")

            HStack {
                Button("Primary Action") { statusText = "primary tapped" }
                    .accessibilityIdentifier("btn-primary")

                Button("Secondary Action") { statusText = "secondary tapped" }
                    .accessibilityIdentifier("btn-secondary")
            }

            TextField("Enter text", text: $inputText)
                .accessibilityIdentifier("input-field")
                .onSubmit { statusText = inputText }

            Toggle("Enable Feature", isOn: $featureEnabled)
                .accessibilityIdentifier("feature-toggle")

            List(1...5, id: \.self) { index in
                Text("Item \(index)")
            }
            .accessibilityIdentifier("item-list")
            .frame(height: 150)

            Button("Open Sheet") { showSheet = true }
                .accessibilityIdentifier("btn-sheet")
        }
        .padding()
        .sheet(isPresented: $showSheet) {
            VStack(spacing: 16) {
                Text("Sheet Content")
                Button("Close") { showSheet = false }
                    .accessibilityIdentifier("btn-sheet-close")
            }
            .padding()
        }
    }
}
