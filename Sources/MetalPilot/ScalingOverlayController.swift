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
    public enum RecoveryStatus {
        case started(String)
        case succeeded(String)
        case failed(String)
    }

    public static let shared = ScalingOverlayController()

    private var overlayWindow: NSWindow?
    private var mtkView: MTKView?
    public private(set) var engine: ScalingEngine?
    public private(set) var captureService: WindowCaptureService?
    public private(set) var isActive: Bool = false

    public var onRecoveryStatus: ((RecoveryStatus) -> Void)?

    private var mouseTrackingTimer: Timer?
    private var startupWatchdogTask: Task<Void, Never>?
    private var healthWatchdogTask: Task<Void, Never>?
    private var recoveryTask: Task<Void, Never>?
    private var recoveryResetTask: Task<Void, Never>?
    private var hasFrameReady = false
    private var isRecovering = false
    private var recoveryAttempts = 0
    private var lastRecoveryAt: Date?
    private var shouldResumeAfterInterruption = false
    private var activeTargetWindow: TargetWindowInfo?
    private var activeSettings: ScalingSettings?

    private let maximumRecoveryAttempts = 3
    private let recoveryWindow: TimeInterval = 120
    private let recoveryCooldown: TimeInterval = 20
    private let captureSilenceTimeout: TimeInterval = 12

    private override init() {
        super.init()
        self.engine = ScalingEngine()
        self.captureService = WindowCaptureService()
        installLifecycleObservers()

        self.engine?.onFrameReady = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.hasFrameReady = true
                self.startupWatchdogTask?.cancel()
                self.overlayWindow?.orderFrontRegardless()

                guard self.isRecovering else { return }
                self.isRecovering = false
                self.notifyRecovery(.succeeded(tr("画面捕捉已自动恢复", "Capture recovered automatically", "画面キャプチャを自動復旧しました")))
                self.scheduleRecoveryReset()
            }
        }
        self.captureService?.onCaptureFailure = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.requestRecovery(reason: tr("捕捉流异常", "Capture stream failure", "キャプチャストリーム異常"))
            }
        }
        self.captureService?.onFrameReceived = { [weak self] surface, pixelBuffer, timestamp, isSceneCut in
            self?.engine?.processCapturedFrame(
                surface: surface,
                pixelBuffer: pixelBuffer,
                timestamp: timestamp,
                isSceneCut: isSceneCut
            )
        }
    }

    public func start(targetWindow: TargetWindowInfo, settings: ScalingSettings, cancelRecoveryTask: Bool = true) async -> Bool {
        await stop(cancelRecoveryTask: cancelRecoveryTask)
        activeTargetWindow = targetWindow
        activeSettings = settings
        hasFrameReady = false

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
        // Keep the overlay hidden until a captured frame has become a renderable
        // Metal texture. An empty MTKView must never cover the game with black.

        isActive = true
        let renderScale = settings.renderScale.rawValue
        let started = await captureService?.startCapture(
            windowID: targetWindow.id,
            maxFPS: 0,
            showsCursor: false,
            renderScale: renderScale,
            queueDepth: 3
        ) ?? false

        if started {
            startMouseTracking(targetBounds: targetWindow.bounds)
            startHealthWatchdog()
            startupWatchdogTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.isActive, !self.hasFrameReady else { return }
                self.requestRecovery(
                    reason: tr("启动后没有收到可渲染画面", "No renderable frame received during startup", "起動後に描画可能なフレームを受信できませんでした"),
                    bypassCooldown: true
                )
            }
            return true
        } else {
            await stop(cancelRecoveryTask: cancelRecoveryTask)
            return false
        }
    }

    public func stop(cancelRecoveryTask: Bool = true) async {
        if cancelRecoveryTask {
            recoveryTask?.cancel()
            recoveryTask = nil
            recoveryResetTask?.cancel()
            recoveryResetTask = nil
            isRecovering = false
            recoveryAttempts = 0
            lastRecoveryAt = nil
            shouldResumeAfterInterruption = false
        }

        startupWatchdogTask?.cancel()
        startupWatchdogTask = nil
        healthWatchdogTask?.cancel()
        healthWatchdogTask = nil
        mouseTrackingTimer?.invalidate()
        mouseTrackingTimer = nil

        // Hide and release the overlay before awaiting ScreenCaptureKit. If the
        // capture daemon is stuck, the game must still become visible and usable.
        isActive = false
        hasFrameReady = false
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        mtkView = nil
        engine?.reset()

        await captureService?.stopCapture()
    }

    public func emergencyStop() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.stop()
        }
    }

    private func installLifecycleObservers() {
        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.requestRecovery(reason: tr("显示器或屏幕布局发生变化", "Display configuration changed", "ディスプレイ構成が変更されました"))
            }
        }

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.shouldResumeAfterInterruption = true
                await self.stop(cancelRecoveryTask: false)
            }
        }
        workspaceCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.shouldResumeAfterInterruption else { return }
                self.shouldResumeAfterInterruption = false
                self.requestRecovery(
                    reason: tr("系统唤醒后重新连接捕捉流", "Reconnecting capture after wake", "スリープ復帰後にキャプチャを再接続しています"),
                    allowInactive: true
                )
            }
        }
        workspaceCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                self.shouldResumeAfterInterruption = true
                await self.stop(cancelRecoveryTask: false)
            }
        }
        workspaceCenter.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.shouldResumeAfterInterruption else { return }
                self.shouldResumeAfterInterruption = false
                self.requestRecovery(
                    reason: tr("用户会话恢复后重新连接捕捉流", "Reconnecting capture after session resume", "ユーザーセッション復帰後にキャプチャを再接続しています"),
                    allowInactive: true
                )
            }
        }
    }

    private func startHealthWatchdog() {
        healthWatchdogTask?.cancel()
        healthWatchdogTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, self.isActive else { return }
                guard self.isTargetApplicationFrontmost else { continue }
                guard let lastFrameAt = self.captureService?.health.lastCompleteFrameAt else { continue }
                guard Date().timeIntervalSince(lastFrameAt) >= self.captureSilenceTimeout else { continue }
                self.requestRecovery(reason: tr("捕捉画面长时间没有更新", "Capture frames stopped updating", "キャプチャフレームの更新が停止しました"))
            }
        }
    }

    private func requestRecovery(reason: String, allowInactive: Bool = false, bypassCooldown: Bool = false) {
        guard (isActive || allowInactive), activeTargetWindow != nil, activeSettings != nil else { return }
        guard recoveryTask == nil else { return }

        let now = Date()
        if let lastRecoveryAt {
            if now.timeIntervalSince(lastRecoveryAt) > recoveryWindow {
                recoveryAttempts = 0
            } else if !bypassCooldown && now.timeIntervalSince(lastRecoveryAt) < recoveryCooldown {
                return
            }
        }
        guard recoveryAttempts < maximumRecoveryAttempts else {
            finishRecoveryFailure(reason: reason)
            return
        }

        recoveryTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performRecovery(reason: reason)
            self.recoveryTask = nil
        }
    }

    private func performRecovery(reason: String) async {
        guard let target = activeTargetWindow, let settings = activeSettings else { return }
        isRecovering = true

        while !Task.isCancelled && recoveryAttempts < maximumRecoveryAttempts {
            recoveryAttempts += 1
            lastRecoveryAt = Date()
            let prefix = tr(
                "检测到捕捉异常，正在自动恢复（第\(recoveryAttempts)/\(maximumRecoveryAttempts)次）",
                "Capture issue detected; recovering (attempt \(recoveryAttempts)/\(maximumRecoveryAttempts))",
                "キャプチャ異常を検出、自動復旧中（\(recoveryAttempts)/\(maximumRecoveryAttempts)回目）")
            notifyRecovery(.started("\(prefix)：\(reason)"))

            await stop(cancelRecoveryTask: false)
            guard !Task.isCancelled else {
                isRecovering = false
                return
            }

            guard let windows = try? await WindowCaptureService.getAvailableWindows(),
                  let latestTarget = recoveryTarget(in: windows, matching: target) else {
                if recoveryAttempts < maximumRecoveryAttempts {
                    try? await Task.sleep(for: .seconds(1))
                    continue
                }
                break
            }

            activeTargetWindow = latestTarget
            guard !Task.isCancelled else {
                isRecovering = false
                return
            }
            if await start(targetWindow: latestTarget, settings: settings, cancelRecoveryTask: false) {
                return
            }

            if recoveryAttempts < maximumRecoveryAttempts {
                try? await Task.sleep(for: .seconds(1))
            }
        }

        guard !Task.isCancelled else {
            isRecovering = false
            return
        }

        isRecovering = false
        await stop(cancelRecoveryTask: false)
        let prefix = tr(
            "自动恢复失败，已移除画质覆盖层，原始游戏画面已恢复。请切换到无边框窗口后重试。",
            "Automatic recovery failed. The overlay was removed; the original game view should be restored. Try borderless window mode.",
            "自動復旧に失敗しました。オーバーレイを解除しました。ボーダーレスウィンドウで再試行してください。")
        notifyRecovery(.failed("\(prefix)：\(reason)"))
    }

    private func finishRecoveryFailure(reason: String) {
        isRecovering = false
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.stop(cancelRecoveryTask: false)
            let prefix = tr(
                "自动恢复次数已达上限，已移除画质覆盖层。",
                "Recovery retry limit reached; the overlay was removed.",
                "自動復旧の試行回数上限に達したため、オーバーレイを解除しました。")
            self.notifyRecovery(.failed("\(prefix)：\(reason)"))
        }
    }

    private func recoveryTarget(in windows: [TargetWindowInfo], matching target: TargetWindowInfo) -> TargetWindowInfo? {
        if let exact = windows.first(where: { $0.id == target.id }) {
            return exact
        }
        if let bundleID = target.bundleID,
           let sameWindow = windows.first(where: { $0.bundleID == bundleID && $0.title == target.title }) {
            return sameWindow
        }
        let sameApplication = windows.filter { window in
            if let bundleID = target.bundleID {
                return window.bundleID == bundleID
            }
            return window.appName == target.appName
        }
        return sameApplication.count == 1 ? sameApplication.first : nil
    }

    private var isTargetApplicationFrontmost: Bool {
        guard let bundleID = activeTargetWindow?.bundleID else { return true }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID
    }

    private func scheduleRecoveryReset() {
        recoveryResetTask?.cancel()
        recoveryResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(45))
            guard let self, !Task.isCancelled, self.isActive else { return }
            self.recoveryAttempts = 0
            self.lastRecoveryAt = nil
        }
    }

    private func notifyRecovery(_ status: RecoveryStatus) {
        onRecoveryStatus?(status)
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
