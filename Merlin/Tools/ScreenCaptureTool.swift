@preconcurrency import ScreenCaptureKit
import AppKit
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation

enum ScreenCaptureError: Error, Sendable {
    case permissionDenied
    case noDisplayFound
    case encodingFailed
}

enum ScreenCaptureTool {
    private static let sampleQueue = DispatchQueue(label: "com.merlin.screen-capture.sample")

    static func captureDisplay(quality: Double) async throws -> Data {
        let (data, _) = try await captureDisplayWithSize(quality: quality)
        return data
    }

    static func captureDisplayWithSize(quality: Double) async throws -> (Data, CGSize) {
        try preflightScreenCaptureAccess()

        let content = try await shareableContent()
        guard let display = content.displays.first else {
            throw ScreenCaptureError.noDisplayFound
        }

        let width = max(1, display.width)
        let height = max(1, display.height)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = makeConfiguration(width: width, height: height)
        let image = try await captureImage(filter: filter, configuration: configuration)
        guard let data = jpegData(from: image, quality: quality) else {
            throw ScreenCaptureError.encodingFailed
        }

        return (data, CGSize(width: width, height: height))
    }

    static func captureWindow(bundleID: String, quality: Double) async throws -> Data {
        try preflightScreenCaptureAccess()

        let content = try await shareableContent()
        guard let window = content.windows.first(where: {
            $0.owningApplication?.bundleIdentifier == bundleID
        }) else {
            throw ScreenCaptureError.noDisplayFound
        }

        let size = window.frame.size
        let width = max(1, Int(size.width.rounded(.up)))
        let height = max(1, Int(size.height.rounded(.up)))
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = makeConfiguration(width: width, height: height)
        let image = try await captureImage(filter: filter, configuration: configuration)
        guard let data = jpegData(from: image, quality: quality) else {
            throw ScreenCaptureError.encodingFailed
        }

        return data
    }

    private static func preflightScreenCaptureAccess() throws {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureError.permissionDenied
        }
    }

    private static func shareableContent() async throws -> SCShareableContent {
        do {
            return try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if CGPreflightScreenCaptureAccess() == false {
                throw ScreenCaptureError.permissionDenied
            }
            throw error
        }
    }

    private static func makeConfiguration(width: Int, height: Int) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 1
        configuration.capturesAudio = false
        configuration.showsCursor = false
        return configuration
    }

    private static func captureImage(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws -> CGImage {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        let collector = FirstFrameCollector()
        try stream.addStreamOutput(collector, type: .screen, sampleHandlerQueue: sampleQueue)
        return try await collector.capture(from: stream)
    }

    private static func jpegData(from image: CGImage, quality: Double) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        let clampedQuality = max(0.0, min(1.0, quality))
        return rep.representation(using: .jpeg, properties: [.compressionFactor: clampedQuality])
    }
}

private final class FirstFrameCollector: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private let ciContext = CIContext()
    private var continuation: CheckedContinuation<CGImage, Error>?
    private var stream: SCStream?
    private var completed = false

    func capture(from stream: SCStream) async throws -> CGImage {
        self.stream = stream
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()

            Task {
                do {
                    try await stream.startCapture()
                } catch {
                    finish(throwing: error)
                }
            }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else {
            return
        }

        guard let image = image(from: sampleBuffer) else {
            return
        }

        finish(returning: image)
    }

    private func image(from sampleBuffer: CMSampleBuffer) -> CGImage? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        return ciContext.createCGImage(ciImage, from: ciImage.extent)
    }

    private func finish(returning image: CGImage) {
        let continuation = takeContinuation()
        guard let continuation else {
            return
        }

        continuation.resume(returning: image)
        stopCapture()
    }

    private func finish(throwing error: Error) {
        let continuation = takeContinuation()
        guard let continuation else {
            return
        }

        continuation.resume(throwing: error)
        stopCapture()
    }

    private func takeContinuation() -> CheckedContinuation<CGImage, Error>? {
        lock.lock()
        defer { lock.unlock() }

        guard completed == false else {
            return nil
        }

        completed = true
        let continuation = self.continuation
        self.continuation = nil
        return continuation
    }

    private func stopCapture() {
        guard let stream else {
            return
        }

        Task {
            try? await stream.stopCapture()
        }
    }
}
