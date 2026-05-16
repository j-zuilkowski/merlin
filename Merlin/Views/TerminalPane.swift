import AppKit
import SwiftUI

struct TerminalPane: View {
    let workingDirectory: String

    @StateObject private var viewModel = ShellStreamViewModel()
    @State private var command: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            Group {
                if viewModel.records.isEmpty, viewModel.status == .idle {
                    placeholder
                } else {
                    outputList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                TextField("Shell command", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityIdentifier(AccessibilityID.terminalPaneInput)
                    .onSubmit(runCommand)

                Text(workingDirectory.isEmpty ? "Current working directory" : workingDirectory)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Run", action: runCommand)
                .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.status == .running)
                .accessibilityIdentifier(AccessibilityID.terminalPaneRunButton)

            Button("Stop") {
                viewModel.cancel()
            }
            .disabled(viewModel.status != .running)
            .accessibilityIdentifier(AccessibilityID.terminalPaneStopButton)

            Spacer(minLength: 12)

            statusBadge
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(.caption.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12), in: Capsule())
    }

    private var outputList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.records) { record in
                        recordRow(record)
                            .id(record.id)
                    }
                }
                .padding(12)
            }
            .onChange(of: viewModel.records.count) { _, _ in
                guard let last = viewModel.records.last else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func recordRow(_ record: ShellStreamViewModel.StreamRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(record.kind == .stderr ? "stderr" : "stdout")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(record.isError ? .red : .secondary)
                .frame(width: 48, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.text.isEmpty ? " " : record.text)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(record.isError ? .red : .primary)
                    .textSelection(.enabled)

                if let exitStatus = record.exitStatus {
                    Text("exit \(exitStatus)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(exitStatus == 0 ? .green : .orange)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No shell command has run yet.")
                .font(.headline)
            Text("Enter a command above and run it to stream stdout, stderr, and the exit status.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }

    private var statusLabel: String {
        switch viewModel.status {
        case .idle:
            return "Idle"
        case .running:
            return "Streaming"
        case .finished(let exitStatus):
            return "Exit \(exitStatus)"
        case .failed:
            return "Error"
        case .cancelled:
            return "Cancelled"
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .idle:
            return .secondary
        case .running:
            return .blue
        case .finished(let exitStatus):
            return exitStatus == 0 ? .green : .orange
        case .failed, .cancelled:
            return .red
        }
    }

    private func runCommand() {
        viewModel.start(command: command, cwd: workingDirectory.isEmpty ? nil : workingDirectory)
    }
}
