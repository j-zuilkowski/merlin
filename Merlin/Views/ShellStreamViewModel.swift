import Foundation

@MainActor
final class ShellStreamViewModel: ObservableObject {
    struct StreamRecord: Identifiable, Sendable {
        let id = UUID()
        let kind: ShellOutputLine.Source
        let text: String
        let timestamp: Date
        var exitStatus: Int32? = nil

        var isError: Bool {
            kind == .stderr
        }
    }

    enum Status: Equatable {
        case idle
        case running
        case finished(exitStatus: Int32)
        case failed(message: String)
        case cancelled
    }

    @Published private(set) var records: [StreamRecord] = []
    @Published private(set) var status: Status = .idle
    @Published private(set) var exitStatus: Int32? = nil

    private let streamFactory: @Sendable (String, String?) -> AsyncThrowingStream<ShellOutputLine, Error>
    private var activeTask: Task<Void, Never>?

    init(streamFactory: @escaping @Sendable (String, String?) -> AsyncThrowingStream<ShellOutputLine, Error> = { command, cwd in
        ShellTool.stream(command: command, cwd: cwd)
    }) {
        self.streamFactory = streamFactory
    }

    func start(command: String, cwd: String? = nil) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        cancel()
        records = []
        exitStatus = nil
        status = .running

        activeTask = Task { [streamFactory] in
            await consume(command: trimmed, cwd: cwd, streamFactory: streamFactory)
        }
    }

    func cancel() {
        activeTask?.cancel()
        activeTask = nil
        if status == .running {
            status = .cancelled
        }
    }

    private func consume(command: String,
                         cwd: String?,
                         streamFactory: @escaping @Sendable (String, String?) -> AsyncThrowingStream<ShellOutputLine, Error>) async {
        defer { activeTask = nil }

        do {
            let stream = streamFactory(command, cwd)
            for try await line in stream {
                if Task.isCancelled {
                    status = .cancelled
                    return
                }

                if let exitStatus = line.exitStatus {
                    self.exitStatus = exitStatus
                    if records.isEmpty {
                        records.append(StreamRecord(
                            kind: line.source,
                            text: line.text,
                            timestamp: Date(),
                            exitStatus: exitStatus
                        ))
                    } else {
                        records[records.count - 1].exitStatus = exitStatus
                    }
                    status = .finished(exitStatus: exitStatus)
                    continue
                }

                records.append(StreamRecord(
                    kind: line.source,
                    text: line.text,
                    timestamp: Date()
                ))
            }

            if Task.isCancelled {
                status = .cancelled
                return
            }

            let resolvedExitStatus = exitStatus ?? 0
            if exitStatus == nil {
                if records.isEmpty {
                    records.append(StreamRecord(
                        kind: .stdout,
                        text: "",
                        timestamp: Date(),
                        exitStatus: resolvedExitStatus
                    ))
                } else {
                    records[records.count - 1].exitStatus = resolvedExitStatus
                }
                self.exitStatus = resolvedExitStatus
            }
            status = .finished(exitStatus: resolvedExitStatus)
        } catch {
            if Task.isCancelled || status == .cancelled {
                status = .cancelled
            } else {
                status = .failed(message: error.localizedDescription)
            }
        }
    }
}
