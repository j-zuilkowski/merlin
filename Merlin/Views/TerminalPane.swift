import AppKit
import SwiftUI
import Darwin

struct TerminalPane: View {
    let workingDirectory: String

    var body: some View {
        TerminalViewRepresentable(workingDirectory: workingDirectory)
    }
}

private struct TerminalViewRepresentable: NSViewRepresentable {
    let workingDirectory: String

    func makeCoordinator() -> TerminalCoordinator {
        TerminalCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = TerminalTextView()
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isRichText = false
        textView.isEditable = false
        textView.isSelectable = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.usesFindBar = false

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        context.coordinator.attach(textView: textView)
        context.coordinator.start(workingDirectory: workingDirectory)
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

private final class TerminalTextView: NSTextView {
    weak var terminalSession: PTYSession?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard let input = TerminalInputTranslator.translate(event: event) else {
            super.keyDown(with: event)
            return
        }

        Task { await terminalSession?.send(input) }
    }

    override func paste(_ sender: Any?) {
        guard let string = NSPasteboard.general.string(forType: .string), !string.isEmpty else { return }
        Task { await terminalSession?.send(string) }
    }
}

@MainActor
private final class TerminalCoordinator: NSObject, @unchecked Sendable {
    private let session = PTYSession()
    private weak var textView: TerminalTextView?
    private var readTask: Task<Void, Never>?

    func attach(textView: TerminalTextView) {
        self.textView = textView
        textView.terminalSession = session
    }

    func start(workingDirectory: String) {
        readTask?.cancel()
        readTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try await session.launch(workingDirectory: workingDirectory)
                for try await chunk in stream {
                    if Task.isCancelled { break }
                    await MainActor.run { [weak self] in
                        self?.append(chunk)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.append("\n[terminal] \(error.localizedDescription)\n")
                }
            }
        }
    }

    @MainActor
    private func append(_ text: String) {
        guard let textView else { return }
        guard let storage = textView.textStorage else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: textView.textColor ?? NSColor.textColor
        ]
        storage.append(NSAttributedString(string: text, attributes: attrs))
        textView.scrollToEndOfDocument(nil)
    }
}

private actor PTYSession {
    private var masterFD: Int32 = -1
    private var childPID: pid_t = -1
    private var isRunning = false

    func launch(workingDirectory: String) throws -> AsyncThrowingStream<String, Error> {
        if isRunning {
            stop()
        }

        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else {
            throw PTYError.open(errno)
        }

        guard grantpt(master) == 0 else {
            close(master)
            throw PTYError.grant(errno)
        }

        guard unlockpt(master) == 0 else {
            close(master)
            throw PTYError.unlock(errno)
        }

        var slaveNameBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard ptsname_r(master, &slaveNameBuffer, slaveNameBuffer.count) == 0 else {
            close(master)
            throw PTYError.ptsName(errno)
        }

        let slaveFD = open(slaveNameBuffer, O_RDWR)
        guard slaveFD >= 0 else {
            close(master)
            throw PTYError.open(errno)
        }

        let pid = c_fork()
        guard pid >= 0 else {
            close(master)
            close(slaveFD)
            throw PTYError.fork(errno)
        }

        if pid == 0 {
            let cwd = workingDirectory.isEmpty
                ? FileManager.default.currentDirectoryPath
                : workingDirectory
            _ = chdir(cwd)

            setenv("TERM", "xterm-256color", 1)
            setenv("COLORTERM", "truecolor", 1)

            _ = login_tty(slaveFD)
            close(master)

            let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            shellPath.withCString { shellC in
                let argv: [UnsafeMutablePointer<CChar>?] = [
                    strdup(shellPath),
                    strdup("-l"),
                    nil
                ]
                argv.withUnsafeBufferPointer { buffer in
                    _ = execvp(shellC, buffer.baseAddress)
                }
            }

            _exit(127)
        }

        close(slaveFD)
        masterFD = master
        childPID = pid
        isRunning = true

        let fd = master
        return AsyncThrowingStream { continuation in
            let reader = Task.detached(priority: .background) {
                var buffer = [UInt8](repeating: 0, count: 4096)

                while !Task.isCancelled {
                    let count = read(fd, &buffer, buffer.count)
                    if count > 0 {
                        let chunk = String(decoding: buffer.prefix(count), as: UTF8.self)
                        continuation.yield(chunk)
                        continue
                    }

                    if count == 0 {
                        break
                    }

                    if errno == EINTR {
                        continue
                    }

                    continuation.yield("\n[terminal] read failed: \(String(cString: strerror(errno)))\n")
                    break
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                reader.cancel()
            }
        }
    }

    func send(_ text: String) {
        guard masterFD >= 0 else { return }
        text.withCString { ptr in
            _ = write(masterFD, ptr, strlen(ptr))
        }
    }

    func stop() {
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }

        if childPID > 0 {
            kill(childPID, SIGTERM)
            childPID = -1
        }

        isRunning = false
    }
}

@_silgen_name("fork")
private func c_fork() -> pid_t

private enum PTYError: LocalizedError {
    case open(Int32)
    case grant(Int32)
    case unlock(Int32)
    case ptsName(Int32)
    case fork(Int32)

    var errorDescription: String? {
        switch self {
        case .open(let code):
            return "Failed to open PTY (\(code))."
        case .grant(let code):
            return "Failed to grant PTY permissions (\(code))."
        case .unlock(let code):
            return "Failed to unlock PTY (\(code))."
        case .ptsName(let code):
            return "Failed to resolve PTY name (\(code))."
        case .fork(let code):
            return "Failed to fork PTY child (\(code))."
        }
    }
}

private enum TerminalInputTranslator {
    static func translate(event: NSEvent) -> String? {
        if event.modifierFlags.contains(.command) {
            return nil
        }

        if let scalar = event.charactersIgnoringModifiers?.unicodeScalars.first {
            switch scalar.value {
            case 0x0D, 0x0A:
                return "\n"
            case 0x7F:
                return "\u{7f}"
            case 0x09:
                return "\t"
            default:
                break
            }
        }

        if event.modifierFlags.contains(.control),
           let character = event.charactersIgnoringModifiers?.lowercased().first,
           let value = character.asciiValue {
            let controlValue = value & 0x1F
            return String(UnicodeScalar(controlValue))
        }

        if let characters = event.characters, !characters.isEmpty {
            return characters
        }

        switch event.keyCode {
        case 123:
            return "\u{1b}[D"
        case 124:
            return "\u{1b}[C"
        case 125:
            return "\u{1b}[B"
        case 126:
            return "\u{1b}[A"
        default:
            return nil
        }
    }
}
