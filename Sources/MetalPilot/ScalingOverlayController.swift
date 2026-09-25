import Foundation
import AppKit
import MetalKit
#if SWIFT_PACKAGE
import MetalPilotCore
#endif

public final class NonActivatingWindow: NSWindow {
    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

@MainActor
public final class ScalingOverlayController: NSObject {
    public static let shared = ScalingOverlayController()

    private var overlayWindow: NSWindow?
    private var mtkView: MTKView?
    public private(set) var engine: ScalingEngine?
    public private(set) var captureService: WindowCaptureService?
    public private(set) var isActive: Bool = false

    private var mouseTrackingTimer: Timer?

    private override init() {
        super.init()
        self.engine = ScalingEngine()
        self.captureService = WindowCaptureService()

        self.captureService?.onFrameReceived = { [weak self] surface, pixelBuffer, timestamp, isSceneCut in
            self?.engine?.processCapturedFrame(
                surface: surface,
                pixelBuffer: pixelBuffer,
                timestamp: timestamp,
                isSceneCut: isSceneCut
            )
        }
    }

    public func start(targetWindow: TargetWindowInfo, settings: ScalingSettings) async -> Bool {
        await stop()

        guard let engine else { return false }
        engine.settings = settings

        let screen = NSScreen.screens.first { $0.frame.intersects(targetWindow.bounds) } ?? NSScreen.main
        guard let targetScreen = screen else { return false }

        let window = NonActivatingWindow(
            contentRect: targetWindow.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: targetScreen
        )

        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.acceptsMouseMovedEvents = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = MTKView(frame: NSRect(origin: .zero, size: targetWindow.bounds.size))
        engine.setMTKView(view)
        window.contentView = view

        self.overlayWindow = window
        self.mtkView = view
        window.orderFrontRegardless()

        let renderScale = settings.renderScale.rawValue
        let started = await captureService?.startCapture(
            windowID: targetWindow.id,
            maxFPS: 0,
            showsCursor: false,
            renderScale: renderScale,
            queueDepth: 3
        ) ?? false

        if started {
            isActive = true
            startMouseTracking(targetBounds: targetWindow.bounds)
            return true
        } else {
            await stop()
            return false
        }
    }

    public func stop() async {
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = nil
        await captureService?.stopCapture()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        mtkView = nil
        engine?.reset()
        isActive = false
    }

    private func startMouseTracking(targetBounds: CGRect) {
        mouseTrackingTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                let mouseLoc = NSEvent.mouseLocation
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                let flippedY = primaryHeight - mouseLoc.y
                let localX = mouseLoc.x - targetBounds.origin.x
                let localY = flippedY - targetBounds.origin.y
                let isInside = targetBounds.contains(CGPoint(x: mouseLoc.x, y: flippedY))

                self.engine?.updateCursor(
                    position: CGPoint(x: localX, y: localY),
                    windowBounds: targetBounds,
                    isVisible: isInside
                )
            }
        }
    }
}
