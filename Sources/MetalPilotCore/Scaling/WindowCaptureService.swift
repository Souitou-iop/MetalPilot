import Foundation
import AppKit
import ScreenCaptureKit
import CoreGraphics
import CoreMedia
import CoreVideo
@preconcurrency import IOSurface
import os

public struct CaptureHealth: Sendable {
    public let lastCompleteFrameAt: Date?
    public let lastChangedFrameAt: Date?
    public let frameSize: CGSize

    public init(lastCompleteFrameAt: Date?, lastChangedFrameAt: Date?, frameSize: CGSize) {
        self.lastCompleteFrameAt = lastCompleteFrameAt
        self.lastChangedFrameAt = lastChangedFrameAt
        self.frameSize = frameSize
    }
}

public struct TargetWindowInfo: Identifiable, Sendable {
    public let id: CGWindowID
    public let title: String
    public let appName: String
    public let bundleID: String?
    public let bounds: CGRect
    public let isOnScreen: Bool

    public init(id: CGWindowID, title: String, appName: String, bundleID: String?, bounds: CGRect, isOnScreen: Bool) {
        self.id = id
        self.title = title
        self.appName = appName
        self.bundleID = bundleID
        self.bounds = bounds
        self.isOnScreen = isOnScreen
    }
}

public final class WindowCaptureService: NSObject, SCStreamDelegate, SCStreamOutput, @unchecked Sendable {
    private let captureQueue = DispatchQueue(label: "com.metalpilot.scaling.capture", qos: .userInteractive)

    public private(set) var lastError: String?
    private var stream: SCStream?

    private let configLock = OSAllocatedUnfairLock()
    private let healthLock = OSAllocatedUnfairLock()
    private var _basePixelSize: CGSize = .zero
    private var _currentRenderScale: Float = 1.0
    private var _capturePixelSize: CGSize = .zero
    private var _maxFPS: Int = 0
    private var _showsCursor: Bool = false
    private var _queueDepth: Int = 3

    public var capturePixelSize: CGSize {
        configLock.lock()
        defer { configLock.unlock() }
        return _capturePixelSize
    }

    public var nativePixelSize: CGSize {
        configLock.lock()
        defer { configLock.unlock() }
        return _basePixelSize
    }

    private var lastFrameSignature: UInt64 = 0
    private var hasLastSignature = false
    private var lastCompleteFrameAt: Date?
    private var lastChangedFrameAt: Date?
    private var lastFrameSize: CGSize = .zero
    private let sceneCutDetector = SceneCutDetector()

    public var health: CaptureHealth {
        healthLock.withLock {
            CaptureHealth(
                lastCompleteFrameAt: lastCompleteFrameAt,
                lastChangedFrameAt: lastChangedFrameAt,
                frameSize: lastFrameSize
            )
        }
    }

    public var onFrameReceived: ((_ surface: IOSurfaceRef, _ pixelBuffer: CVPixelBuffer, _ timestamp: Double, _ isSceneCut: Bool) -> Void)?
    public var onCaptureFailure: ((String) -> Void)?

    public override init() {
        super.init()
    }

    public static func getAvailableWindow(id: CGWindowID) async throws -> TargetWindowInfo? {
        try await getAvailableWindows().first(where: { $0.id == id })
    }

    public static func getAvailableWindows() async throws -> [TargetWindowInfo] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        var result: [TargetWindowInfo] = []
        for win in content.windows {
            // Filter out system windows, tiny windows, and our own overlay windows
            guard win.frame.width > 100, win.frame.height > 100 else { continue }
            let appName = win.owningApplication?.applicationName ?? "Unknown"
            let bundleID = win.owningApplication?.bundleIdentifier
            if bundleID == Bundle.main.bundleIdentifier { continue }
            let title = win.title ?? appName
            result.append(TargetWindowInfo(
                id: win.windowID,
                title: title,
                appName: appName,
                bundleID: bundleID,
                bounds: win.frame,
                isOnScreen: win.isOnScreen
            ))
        }
        return result
    }

    private static func backingScale(for windowFrame: CGRect) -> CGFloat {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cocoaFrame = CGRect(
            x: windowFrame.origin.x,
            y: primaryHeight - windowFrame.maxY,
            width: windowFrame.width,
            height: windowFrame.height
        )
        let screen = NSScreen.screens.first { $0.frame.intersects(cocoaFrame) } ?? NSScreen.main
        return screen?.backingScaleFactor ?? 1.0
    }

    private static let minimumCaptureDimension: CGFloat = 16

    private func makeConfiguration(renderScale: Float) -> SCStreamConfiguration {
        configLock.lock()
        let scaled = CGSize(
            width: max(Self.minimumCaptureDimension, (_basePixelSize.width * CGFloat(renderScale)).rounded()),
            height: max(Self.minimumCaptureDimension, (_basePixelSize.height * CGFloat(renderScale)).rounded()))
        _capturePixelSize = scaled
        _currentRenderScale = renderScale
        let maxFPS = _maxFPS
        let showsCursor = _showsCursor
        let queueDepth = _queueDepth
        configLock.unlock()

        let config = SCStreamConfiguration()
        config.width = Int(scaled.width)
        config.height = Int(scaled.height)
        if maxFPS > 0 {
            config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(maxFPS))
        }
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = showsCursor
        if queueDepth > 0 {
            config.queueDepth = queueDepth
        }
        config.captureResolution = .best
        config.shouldBeOpaque = false
        config.backgroundColor = .clear
        return config
    }

    public func updateRenderScale(_ renderScale: Float) async {
        let (ready, changed) = configLock.withLock { () -> (Bool, Bool) in
            (_basePixelSize != .zero, abs(renderScale - _currentRenderScale) > 0.001)
        }
        guard let stream, ready, changed else { return }
        let config = makeConfiguration(renderScale: renderScale)
        do {
            try await stream.updateConfiguration(config)
        } catch {
            await MainActor.run {
                lastError = "Capture reconfiguration failed: \(error.localizedDescription)"
            }
        }
    }

    public func startCapture(
        windowID: CGWindowID,
        maxFPS: Int = 0,
        showsCursor: Bool = false,
        renderScale: Float = 1.0,
        queueDepth: Int = 3
    ) async -> Bool {
        await stopCapture()

        do {
            let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let targetWindow = availableContent.windows.first(where: { $0.windowID == windowID }) else {
                await MainActor.run { lastError = "Target window not found." }
                return false
            }

            let filter = SCContentFilter(desktopIndependentWindow: targetWindow)
            let scale = Self.backingScale(for: targetWindow.frame)
            let base = CGSize(width: targetWindow.frame.width * scale,
                              height: targetWindow.frame.height * scale)

            configLock.withLock {
                _basePixelSize = base
                _maxFPS = maxFPS
                _showsCursor = showsCursor
                _queueDepth = queueDepth
            }

            let config = makeConfiguration(renderScale: renderScale)
            let captureStream = SCStream(filter: filter, configuration: config, delegate: self)
            try captureStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: captureQueue)
            hasLastSignature = false
            sceneCutDetector.reset()
            healthLock.withLock {
                lastCompleteFrameAt = nil
                lastChangedFrameAt = nil
                lastFrameSize = .zero
            }
            try await captureStream.startCapture()

            self.stream = captureStream
            await MainActor.run {
                lastError = nil
            }
            return true
        } catch {
            let message = "ScreenCaptureKit error: \(error.localizedDescription)"
            await MainActor.run {
                lastError = message
            }
            return false
        }
    }

    public func stopCapture() async {
        if let currentStream = stream {
            do {
                try await currentStream.stopCapture()
            } catch {
                let nsError = error as NSError
                if !(nsError.domain == SCStreamErrorDomain && nsError.code == -3808) {
                    await MainActor.run {
                        lastError = "ScreenCaptureKit stop error: \(error.localizedDescription)"
                    }
                }
            }
        }
        stream = nil
    }

    public nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        let stoppedStreamID = ObjectIdentifier(stream)
        Task { @MainActor in
            let nsError = error as NSError
            if nsError.domain == SCStreamErrorDomain && nsError.code == -3808 { return }
            guard let currentStream = self.stream,
                  ObjectIdentifier(currentStream) == stoppedStreamID else { return }
            let message = "Stream stopped: \(error.localizedDescription)"
            self.lastError = message
            self.stream = nil
            self.onCaptureFailure?(message)
        }
    }

    public nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }

        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let attachments = attachmentsArray.first else {
            return
        }

        guard let statusRawValue = attachments[SCStreamFrameInfo.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRawValue),
              status == .complete else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else { return }

        let frameSize = CGSize(width: IOSurfaceGetWidth(surface), height: IOSurfaceGetHeight(surface))
        healthLock.withLock {
            lastCompleteFrameAt = Date()
            lastFrameSize = frameSize
        }

        let signature = Self.calculateFrameSignature(surface)
        if hasLastSignature && signature == lastFrameSignature {
            return
        }
        lastFrameSignature = signature
        hasLastSignature = true
        healthLock.withLock {
            lastChangedFrameAt = Date()
        }

        let isSceneCut = sceneCutDetector.evaluate(surface: surface)
        let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))

        onFrameReceived?(surface, pixelBuffer, timestamp, isSceneCut)
    }

    private static func calculateFrameSignature(_ surface: IOSurfaceRef) -> UInt64 {
        IOSurfaceLock(surface, .readOnly, nil)
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }

        let base = IOSurfaceGetBaseAddress(surface)
        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let bpr = IOSurfaceGetBytesPerRow(surface)
        guard width > 0, height > 0, bpr > 0 else { return 0 }

        let ptr = base.assumingMemoryBound(to: UInt8.self)
        var hash: UInt64 = 14695981039346656037 // FNV-1a offset basis
        let prime: UInt64 = 1099511628211

        let stepX = max(1, width / 32)
        let stepY = max(1, height / 32)

        for y in stride(from: 0, to: height, by: stepY) {
            let rowOffset = y * bpr
            for x in stride(from: 0, to: width, by: stepX) {
                let pixel = ptr[rowOffset + x * 4]
                hash ^= UInt64(pixel)
                hash = hash &* prime
            }
        }
        return hash
    }
}
