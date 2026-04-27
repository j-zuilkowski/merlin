import Foundation
import Combine
import Speech

final class VoiceDictationEngine: ObservableObject {
    enum State: Equatable {
        case idle
        case recording
        case error(String)
    }

    static let shared = VoiceDictationEngine()

    @Published private(set) var state: State = .idle

    private var onTranscript: ((String) -> Void)?

    func setOnTranscript(_ handler: @escaping (String) -> Void) async {
        onTranscript = handler
    }

    func toggle() async {
        switch state {
        case .idle:
            await startIfAuthorized()
        case .recording:
            await stop()
        case .error:
            state = .idle
        }
    }

    func startIfAuthorized() async {
        guard isRuntimeSpeechAvailable else {
            state = .idle
            return
        }

        let status = await requestAuthorization()
        guard status == .authorized else {
            state = .idle
            return
        }

        state = .recording
    }

    func stop() async {
        state = .idle
    }

    func simulateTranscript(_ text: String) async {
        onTranscript?(text)
    }

    private var isRuntimeSpeechAvailable: Bool {
        ProcessInfo.processInfo.processName != "xctest" &&
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
    }

    private func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
