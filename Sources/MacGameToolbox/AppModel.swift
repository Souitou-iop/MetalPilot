import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers
import Carbon.HIToolbox
import ApplicationServices
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

enum MetalHUDPreset {
    case minimal, balanced, complex
}

@MainActor
final class AppModel: ObservableObject {
    @Published var status = TaskStatus()
    @Published var configuration = AppConfiguration()
    @Published var disks: [DiskVolume] = []
    @Published var selectedDiskIDs = Set<String>()
    @Published var diskPaths: [String: String] = [:]
    @Published var metalHUDEnabled = false
    @Published var cacheScan: CacheScan?
    @Published var showingDiskManager = false
    @Published var showingCacheConfirmation = false
    @Published var cacheConfirmationStage = 0
    @Published var showingChangelog = false
    @Published var showingTutorials = false
    @Published var isHoYoAssistantRunning = false
    @Published var showingProcessSelection = false
    @Published var runningProcesses: [SystemProcess] = []
    @Published var selectedProcessIDs = Set<Int32>()
    @Published var showingMetalHUDProcessManager = false
    @Published var interferingProcesses: [MetalHUDProcess] = []
    @Published var selectedInterferingPIDs = Set<Int32>()
    @Published var isScanningInterferingProcesses = false
    @Published var isTerminatingInterferingProcesses = false
    @Published var isGamingFocusActive = false
    @Published var discoveredBottles: [WineBottle] = []
    @Published var selectedBottleID: String? = nil
    @Published var bottleGameSaves: [GameSaveLocation] = []
    @Published var isScanningSaves = false
    @Published var isBackingUpSave = false
    @Published var healthReport: SystemHealthReport?
    @Published var isCheckingHealth = false
    @Published var isScalingActive: Bool = false
    @Published var availableWindows: [TargetWindowInfo] = []
    @Published var selectedWindowID: CGWindowID? = nil
    @Published var isScanningWindows: Bool = false
    @Published var showingHUDAppLauncher: Bool = false
    @Published var selectedHUDAppPaths: Set<String> = []

    // MARK: iOS Metal HUD launcher (transient, nothing is persisted)
    @Published var showingIOSHUDLauncher: Bool = false
    @Published var iosDevices: [IOSDevice] = []
    @Published var selectedIOSDeviceID: String? = nil
    @Published var iosApps: [IOSInstalledApp] = []
    @Published var selectedIOSBundleIdentifier: String? = nil
    @Published var isRefreshingIOSDevices = false
    @Published var isRefreshingIOSApps = false
    @Published var iosDeviceErrorMessage: String? = nil
    @Published var iosAppErrorMessage: String? = nil
    @Published var iosLaunchConfirmationApp: IOSInstalledApp? = nil
    @Published var iosLaunchArgumentsText: String = ""

    private let privileged = PrivilegedHelperClient()
    private let configurationStore: ConfigurationStore
    private let diskService: DiskService
    private let gamingService: GamingService
    private let hudPresetStore = ManagedHUDPresetStore()
    private let hostnameService: HostnameService
    private let cacheService: CacheService
    private let diagnosticsService = DiagnosticsService()
    private let focusBooster = GamingFocusBooster()
    private let saveFinderService = GameSaveFinderService()
    private let snapshotService = PerformanceSnapshotService()
    private let healthInspector = SystemHealthInspector()
    private var hoyoTask: Task<Void, Never>?
    private var automaticMountTask: Task<Void, Never>?
    private var didLaunch = false

    init() {
        configurationStore = ConfigurationStore()
        diskService = DiskService()
        gamingService = GamingService(privileged: privileged)
        hostnameService = HostnameService(privileged: privileged)
        cacheService = CacheService(privileged: privileged)
        launch()
    }

    func launch() {
        guard !didLaunch else { return }
        didLaunch = true
        DiagnosticFileLogger.write("App launched, version 4.2.0")
        Task {
            do {
                configuration = try await configurationStore.load()
                AppLanguage.currentPreference = configuration.languagePreference
                DispatchQueue.main.async {
                    let localizedTitle = tr("MetalPilot", "MetalPilot", "MetalPilot")
                    for window in NSApp.windows where window.canBecomeMain {
                        window.title = localizedTitle
                    }
                }
            }
            catch { report(error) }
            metalHUDEnabled = await gamingService.metalHUDEnabled()
            if metalHUDEnabled {
                try? await gamingService.setMetalHUD(enabled: true, options: configuration.metalHUDOptions)
            }
            if (try? String(contentsOfFile: "/etc/hosts", encoding: .utf8))?.contains("# BEGIN MAC GAME TOOLBOX HOYO") == true {
                await gamingService.cleanStaleHoYoEntries()
            }
            startAutomaticMountMonitoring()
            checkSystemHealth()
            setupScalingHotkeys()
        }
    }

    private func setupScalingHotkeys() {
        // Cmd + Shift + T (keyCode 17 for 'T', modifiers cmdKey | shiftKey = 0x0100 | 0x0200)
        ScalingHotkeyManager.shared.register(keyCode: 17, modifiers: UInt32(cmdKey | shiftKey)) { [weak self] in
            Task { @MainActor [weak self] in
                self?.toggleScaling()
            }
        }
        // Cmd + Shift + C (keyCode 8 for 'C')
        ScalingHotkeyManager.shared.register(keyCode: 8, modifiers: UInt32(cmdKey | shiftKey)) {
            Task { @MainActor in
                _ = MouseConstraintManager.shared.toggle()
            }
        }
    }

    var isScreenCapturePermissionGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    var isAccessibilityPermissionGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestScreenRecordingPermission() {
        let granted = CGRequestScreenCaptureAccess()
        if !granted {
            openScreenRecordingSettings()
        }
        refreshAvailableWindows()
        checkSystemHealth()
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        if !trusted {
            openAccessibilitySettings()
        }
        checkSystemHealth()
    }

    func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshAvailableWindows() {
        guard !isScanningWindows else { return }
        isScanningWindows = true
        Task {
            if let windows = try? await WindowCaptureService.getAvailableWindows() {
                self.availableWindows = windows
                if self.selectedWindowID == nil || !windows.contains(where: { $0.id == self.selectedWindowID }) {
                    self.selectedWindowID = windows.first?.id
                }
            }
            self.isScanningWindows = false
        }
    }

    func toggleScaling() {
        if isScalingActive {
            stopScaling()
        } else {
            startScaling()
        }
    }

    func startScaling() {
        if !isScreenCapturePermissionGranted {
            _ = CGRequestScreenCaptureAccess()
            setTransientStatus(.failed, message: tr("请先在系统设置中允许屏幕录制权限", "Please grant Screen Recording permission in System Settings"))
            openScreenRecordingSettings()
            return
        }

        guard let windowID = selectedWindowID,
              let targetWindow = availableWindows.first(where: { $0.id == windowID }) else {
            refreshAvailableWindows()
            setTransientStatus(.failed, message: tr("请先选择目标游戏窗口", "Please select a target window"))
            return
        }

        Task {
            let success = await ScalingOverlayController.shared.start(
                targetWindow: targetWindow,
                settings: configuration.scalingSettings
            )
            if success {
                isScalingActive = true
                setTransientStatus(.succeeded, message: tr("已启动画质超分与补帧 (按 ⌘⇧T 可随时关闭)", "Scaling & Frame Gen started (Press ⌘⇧T to toggle)"))
            } else {
                setTransientStatus(.failed, message: tr("启动失败，请检查屏幕录制权限与窗口状态", "Failed to start, check Screen Recording permission"))
            }
        }
    }

    func stopScaling() {
        Task {
            await ScalingOverlayController.shared.stop()
            MouseConstraintManager.shared.disable()
            isScalingActive = false
            setTransientStatus(.succeeded, message: tr("已关闭画质超分与补帧", "Scaling & Frame Gen stopped"))
        }
    }

    func updateScalingSettings(_ settings: ScalingSettings) {
        configuration.scalingSettings = settings
        saveConfiguration()
    }

    func setMetalHUD(_ enabled: Bool) {
        runTask(tr("正在更新 MetalHUD", "Updating MetalHUD")) {
            try await self.gamingService.setMetalHUD(enabled: enabled, options: self.configuration.metalHUDOptions)
            self.metalHUDEnabled = enabled
            return enabled ? tr("MetalHUD 已开启", "MetalHUD enabled") : tr("MetalHUD 已关闭", "MetalHUD disabled")
        }
    }

    func addAppToHUDList() {
        let panel = NSOpenPanel()
        panel.title = tr("添加游戏或应用程序至管理列表", "Add Game or App to Library", "ゲーム・アプリを一覧に追加")
        panel.prompt = tr("添加至列表", "Add to List", "一覧に追加")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK else { return }

        for url in panel.urls {
            rememberMetalHUDApp(url)
        }
        setTransientStatus(.succeeded, message: tr("已添加 \(panel.urls.count) 个游戏/软件", "Added \(panel.urls.count) apps", "\(panel.urls.count) 個のアプリを追加しました"))
    }

    func openHUDAppLauncher() {
        if selectedHUDAppPaths.isEmpty {
            selectedHUDAppPaths = Set(configuration.recentMetalHUDApps.map(\.path))
        }
        showingHUDAppLauncher = true
    }

    // MARK: - iOS Metal HUD Launcher (transient)

    /// Opens the iOS launcher and kicks off a read-only device refresh.
    ///
    /// Nothing here is written to the configuration: device selection and any
    /// launch arguments live only for the current session.
    func openIOSHUDLauncher() {
        showingIOSHUDLauncher = true
        refreshIOSDevices()
    }

    func refreshIOSDevices() {
        guard !isRefreshingIOSDevices else { return }
        isRefreshingIOSDevices = true
        iosDeviceErrorMessage = nil
        Task {
            defer { isRefreshingIOSDevices = false }
            do {
                let devices = try await gamingService.iosDevices()
                guard !Task.isCancelled else { return }
                iosDevices = devices
                iosDeviceErrorMessage = nil
                if let selected = selectedIOSDeviceID, devices.contains(where: { $0.id == selected }) {
                    // Keep the current selection; the app list stays valid.
                } else {
                    // Selection disappeared (device unplugged) — reset to a fresh state.
                    selectedIOSDeviceID = devices.first?.id
                    iosApps = []
                    selectedIOSBundleIdentifier = nil
                    iosAppErrorMessage = nil
                    if selectedIOSDeviceID != nil { refreshIOSApps() }
                }
            } catch {
                iosDevices = []
                iosApps = []
                selectedIOSDeviceID = nil
                selectedIOSBundleIdentifier = nil
                iosDeviceErrorMessage = error.localizedDescription
                DiagnosticFileLogger.write("iOS device enumeration failed: \(error.localizedDescription)")
            }
        }
    }

    func selectIOSDevice(_ deviceID: String?) {
        guard selectedIOSDeviceID != deviceID else { return }
        selectedIOSDeviceID = deviceID
        iosApps = []
        selectedIOSBundleIdentifier = nil
        iosAppErrorMessage = nil
        iosLaunchArgumentsText = ""
        refreshIOSApps()
    }

    func refreshIOSApps() {
        guard let deviceID = selectedIOSDeviceID, !isRefreshingIOSApps else { return }
        isRefreshingIOSApps = true
        iosAppErrorMessage = nil
        Task {
            defer { isRefreshingIOSApps = false }
            do {
                let apps = try await gamingService.iosApps(on: deviceID)
                // Guard against a stale response overwriting a newer device's list.
                guard !Task.isCancelled, selectedIOSDeviceID == deviceID else { return }
                iosApps = apps
                iosAppErrorMessage = nil
                if let selected = selectedIOSBundleIdentifier, !apps.contains(where: { $0.bundleIdentifier == selected }) {
                    selectedIOSBundleIdentifier = nil
                }
            } catch {
                guard selectedIOSDeviceID == deviceID else { return }
                iosApps = []
                selectedIOSBundleIdentifier = nil
                iosAppErrorMessage = error.localizedDescription
                DiagnosticFileLogger.write("iOS app enumeration failed: \(error.localizedDescription)")
            }
        }
    }

    /// Non-empty launch arguments forwarded to `devicectl` for this session only.
    var iosLaunchArguments: [String] {
        iosLaunchArgumentsText
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Asks for confirmation because the launch always terminates an existing instance.
    func requestIOSLaunch(with app: IOSInstalledApp) {
        selectedIOSBundleIdentifier = app.bundleIdentifier
        iosLaunchConfirmationApp = app
    }

    func cancelIOSLaunch() {
        iosLaunchConfirmationApp = nil
    }

    func confirmIOSLaunch() {
        guard let app = iosLaunchConfirmationApp else { return }
        iosLaunchConfirmationApp = nil
        launchIOSAppWithMetalHUD(app)
    }

    private func launchIOSAppWithMetalHUD(_ app: IOSInstalledApp) {
        guard let deviceID = selectedIOSDeviceID else {
            setTransientStatus(.failed, message: tr("请先选择 iOS 设备", "Select an iOS device first", "先に iOS デバイスを選択してください"))
            return
        }
        let arguments: [String]
        do {
            arguments = iosLaunchArguments
            try GamingService.validateIOSLaunchArguments(arguments)
        } catch {
            report(error)
            return
        }

        runTask(tr("正在通过 devicectl 启动 \(app.displayName)…", "Launching \(app.displayName) via devicectl…", "devicectl で \(app.displayName) を起動中…")) {
            try await self.gamingService.launchIOSAppWithMetalHUD(
                deviceID: deviceID,
                bundleIdentifier: app.bundleIdentifier,
                launchArguments: arguments
            )
            // A zero exit only means devicectl accepted the request; the HUD
            // overlay itself is not verified here.
            return tr("已请求启动 \(app.displayName)。命令执行成功，但游戏内 HUD 画面仍需在设备上自行确认。",
                      "Requested launch of \(app.displayName). The command succeeded, but confirm the HUD on the device itself.",
                      "\(app.displayName) の起動を要求しました。コマンドは成功しましたが、HUD 表示は実機で確認してください。")
        }
    }

    var canLaunchIOSApp: Bool {
        selectedIOSDeviceID != nil && selectedIOSBundleIdentifier != nil
    }

    func launchSelectedHUDApps(_ paths: [String]) {
        guard !paths.isEmpty else {
            setTransientStatus(.failed, message: tr("请先勾选要启动的游戏", "Please select at least one game", "起動するゲームを選択してください"))
            return
        }

        showingHUDAppLauncher = false
        runTask(tr("正在启动所选游戏并注入 Metal HUD…", "Launching selected games with Metal HUD…", "選択したゲームを起動中…")) {
            var launchedNames: [String] = []
            var failedNames: [String] = []
            for path in paths {
                let applicationURL = URL(fileURLWithPath: path)
                let name = applicationURL.deletingPathExtension().lastPathComponent
                do {
                    try await self.launchOneAppWithMetalHUD(path: path)
                    self.rememberMetalHUDApp(applicationURL)
                    launchedNames.append(name)
                } catch {
                    DiagnosticFileLogger.write("Launch failed for \(name): \(error.localizedDescription)")
                    failedNames.append(name)
                }
            }
            if failedNames.isEmpty {
                return tr("已启动 \(launchedNames.count) 个游戏：\(launchedNames.joined(separator: ", "))",
                          "Launched \(launchedNames.count) games: \(launchedNames.joined(separator: ", "))",
                          "\(launchedNames.count) 個のゲームを起動しました：\(launchedNames.joined(separator: ", "))")
            }
            // Partial or total failure: surface it instead of counting failures as launches.
            var parts: [String] = []
            if !launchedNames.isEmpty {
                parts.append(tr("已启动 \(launchedNames.count) 个：\(launchedNames.joined(separator: ", "))",
                                "Launched \(launchedNames.count): \(launchedNames.joined(separator: ", "))",
                                "\(launchedNames.count) 個を起動しました：\(launchedNames.joined(separator: ", "))"))
            }
            parts.append(tr("失败 \(failedNames.count) 个：\(failedNames.joined(separator: ", "))",
                            "Failed \(failedNames.count): \(failedNames.joined(separator: ", "))",
                            "失敗 \(failedNames.count) 個：\(failedNames.joined(separator: ", "))"))
            let message = parts.joined(separator: "；")
            if launchedNames.isEmpty {
                throw ToolboxError.commandFailed(message)
            }
            return message
        }
    }

    /// Launches a single app with Metal HUD, honouring the per-app imported preset
    /// priority rule. Throws so callers can report real failures.
    ///
    /// Priority: when this app has an imported preset, the preset's `MTL_HUD_*`
    /// values are the sole environment for this launch and `effectiveOptionsForApp`
    /// is not used. Without a preset the existing per-app/global options apply.
    /// The two sources are never merged field by field.
    private func launchOneAppWithMetalHUD(path: String) async throws {
        let importedPresetPath = configuration.recentMetalHUDApps
            .first { $0.path == path }?
            .importedPreset?
            .path
        try await gamingService.launchWithMetalHUD(
            applicationPath: path,
            options: effectiveOptionsForApp(path: path),
            importedPresetPath: importedPresetPath
        )
    }

    func removeAppFromHUDList(path: String) {
        if let preset = configuration.recentMetalHUDApps.first(where: { $0.path == path })?.importedPreset {
            cleanManagedPreset(preset)
        }
        configuration.recentMetalHUDApps.removeAll { $0.path == path }
        configuration.perAppHUDProfiles.removeAll { $0.appPath == path }
        selectedHUDAppPaths.remove(path)
        saveConfiguration()
    }

    func launchAppWithMetalHUD() {
        let panel = NSOpenPanel()
        panel.title = tr("选择要启用 MetalHUD 的 App", "Choose an app for MetalHUD")
        panel.prompt = tr("启用并打开", "Enable and Open")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        guard panel.runModal() == .OK, let applicationURL = panel.url else { return }

        launchRecordedAppWithMetalHUD(applicationURL.path)
    }

    func launchRecordedAppWithMetalHUD(_ path: String) {
        let applicationURL = URL(fileURLWithPath: path)
        runTask(tr("正在使用 MetalHUD 启动 App", "Launching app with MetalHUD")) {
            try await self.launchOneAppWithMetalHUD(path: path)
            self.rememberMetalHUDApp(applicationURL)
            return tr("已使用 MetalHUD 打开 \(applicationURL.deletingPathExtension().lastPathComponent)", "Opened \(applicationURL.deletingPathExtension().lastPathComponent) with MetalHUD")
        }
    }

    func updateMetalHUDOptions(_ options: MetalHUDOptions) {
        configuration.metalHUDOptions = options
        saveConfiguration()
        if metalHUDEnabled {
            Task {
                try? await gamingService.setMetalHUD(enabled: true, options: options)
            }
        }
    }

    func applyMetalHUDPreset(_ preset: MetalHUDPreset) {
        var options = configuration.metalHUDOptions
        switch preset {
        case .minimal:
            // 基础运行信息：设备、渲染层尺寸、内存、FPS、热状态
            options.elements = ["device", "layersize", "memory", "fps", "thermal"]
        case .balanced:
            // 调优常用：在极简基础上加入 FPS 图表、GPU 时间、帧间隔、Rosetta 信息、游戏模式、MetalFX，便于判断卡顿来源
            options.elements = ["device", "layersize", "memory", "fps", "fpsgraph", "gputime", "frameinterval", "rosetta", "thermal", "gamemode", "metalfx"]
        case .complex:
            // 性能诊断：加入呈现延迟、帧间隔直方图、命令缓冲区与编码器、磁盘、着色器、Rosetta 信息、游戏模式、MetalFX，用于定位卡顿/瓶颈
            options.elements = ["device", "layersize", "memory", "fps", "fpsgraph", "gputime", "frameinterval", "frameintervalgraph", "frameintervalhistogram", "presentdelay", "metalcpu", "shaders", "disk", "toplabeledcommandbuffers", "toplabeledencoders", "rosetta", "thermal", "gamemode", "metalfx"]
        }
        updateMetalHUDOptions(options)
    }

    func currentMetalHUDPreset() -> MetalHUDPreset? {
        let elements = Set(configuration.metalHUDOptions.elements)
        if elements == Set(["device", "layersize", "memory", "fps", "thermal"]) { return .minimal }
        if elements == Set(["device", "layersize", "memory", "fps", "fpsgraph", "gputime", "frameinterval", "rosetta", "thermal", "gamemode", "metalfx"]) { return .balanced }
        if elements == Set(["device", "layersize", "memory", "fps", "fpsgraph", "gputime", "frameinterval", "frameintervalgraph", "frameintervalhistogram", "presentdelay", "metalcpu", "shaders", "disk", "toplabeledcommandbuffers", "toplabeledencoders", "rosetta", "thermal", "gamemode", "metalfx"]) { return .complex }
        return nil
    }

    func chooseMetalHUDReportURL() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = tr("选择", "Choose")
        panel.directoryURL = URL(fileURLWithPath: Self.defaultReportURLPath, isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var options = configuration.metalHUDOptions
        options.reportURL = url.path
        updateMetalHUDOptions(options)
    }

    func useDefaultReportURL() {
        let path = Self.defaultReportURLPath
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        var options = configuration.metalHUDOptions
        options.reportURL = path
        updateMetalHUDOptions(options)
    }

    func clearMetalHUDReportURL() {
        var options = configuration.metalHUDOptions
        options.reportURL = nil
        updateMetalHUDOptions(options)
    }

    func resetMetalHUDOptions() {
        updateMetalHUDOptions(MetalHUDOptions())
        setTransientStatus(.succeeded, message: tr("已重置 Metal HUD 配置", "Metal HUD settings reset"))
    }

    func setNavigationLayoutMode(_ mode: NavigationLayoutMode) {
        configuration.navigationLayoutMode = mode
        saveConfiguration()
    }

    func exportMetalHUDOptions() {
        let panel = NSSavePanel()
        panel.title = tr("导出 Metal HUD 配置", "Export Metal HUD Configuration")
        panel.prompt = tr("导出", "Export")
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "MetalHUD.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(configuration.metalHUDOptions)
            try data.write(to: url)
            setTransientStatus(.succeeded, message: tr("已导出配置", "Configuration exported"))
        } catch {
            report(error)
        }
    }

    func importMetalHUDOptions() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.title = tr("导入 Metal HUD 配置", "Import Metal HUD Configuration")
        panel.prompt = tr("导入", "Import")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let options = try JSONDecoder().decode(MetalHUDOptions.self, from: data)
            updateMetalHUDOptions(options)
            setTransientStatus(.succeeded, message: tr("已导入配置", "Configuration imported"))
        } catch {
            report(error)
        }
    }

    func revealReportURLInFinder() {
        guard let path = configuration.metalHUDOptions.reportURL else { return }
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private static var defaultReportURLPath: String {
        let support = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first
            ?? NSTemporaryDirectory()
        return (support as NSString).appendingPathComponent("MetalPilot/HUDReports")
    }

    func openConsoleApp() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Console") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func exportRecentHUDLogs() {
        let task = Process()
        task.launchPath = "/usr/bin/log"
        task.arguments = ["show", "--predicate", "subsystem == \"com.apple.metal.hud\"", "--last", "10m", "--style", "syslog"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            let output = String(data: data, encoding: .utf8) ?? ""
            let support = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true).first
                ?? NSTemporaryDirectory()
            let dir = (support as NSString).appendingPathComponent("MetalPilot/HUDLogs")
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd_HHmmss"
            let fileName = "MetalHUD_\(formatter.string(from: Date())).log"
            let filePath = (dir as NSString).appendingPathComponent(fileName)
            let header = "Metal HUD Logs (last 10 minutes)\nExported: \(Date())\nFilter: subsystem == \"com.apple.metal.hud\"\n=========================================\n\n"
            let content = header + (output.isEmpty ? "(no logs found)" : output)
            try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
            NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
        } catch {
            report(error)
        }
    }

    func removeRecentMetalHUDApp(_ app: RecentMetalHUDApp) {
        if let preset = app.importedPreset {
            cleanManagedPreset(preset)
        }
        configuration.recentMetalHUDApps.removeAll { $0.path == app.path }
        selectedHUDAppPaths.remove(app.path)
        saveConfiguration()
    }

    func removeRecentMetalHUDApps(paths: Set<String>) {
        for app in configuration.recentMetalHUDApps where paths.contains(app.path) {
            if let preset = app.importedPreset {
                cleanManagedPreset(preset)
            }
        }
        configuration.recentMetalHUDApps.removeAll { paths.contains($0.path) }
        selectedHUDAppPaths.subtract(paths)
        saveConfiguration()
    }

    func openMetalHUDProcessManager() {
        showingMetalHUDProcessManager = true
        selectedInterferingPIDs.removeAll()
        scanInterferingProcesses()
    }

    func scanInterferingProcesses() {
        isScanningInterferingProcesses = true
        let recentPaths = configuration.recentMetalHUDApps.map(\.path)
        Task { @MainActor in
            do {
                let detected = try await gamingService.detectMetalHUDInterferingProcesses(recentAppPaths: recentPaths)
                self.interferingProcesses = detected
                let validPIDs = Set(detected.map(\.pid))
                self.selectedInterferingPIDs = self.selectedInterferingPIDs.intersection(validPIDs)
            } catch {
                self.interferingProcesses = []
                self.selectedInterferingPIDs.removeAll()
            }
            self.isScanningInterferingProcesses = false
        }
    }

    func terminateSelectedInterferingProcesses(force: Bool = false) {
        let pidsToTerminate = Array(selectedInterferingPIDs)
        guard !pidsToTerminate.isEmpty else { return }
        isTerminatingInterferingProcesses = true
        runTask(tr("正在关闭所选进程…", "Terminating selected processes…")) {
            let result = await self.gamingService.terminateProcesses(pids: pidsToTerminate, force: force)
            self.scanInterferingProcesses()
            self.isTerminatingInterferingProcesses = false
            if result.failed.isEmpty {
                return tr("已成功关闭 \(result.succeeded.count) 个进程", "Successfully closed \(result.succeeded.count) process(es)")
            } else {
                return tr("已关闭 \(result.succeeded.count) 个进程，\(result.failed.count) 个进程未能关闭", "Closed \(result.succeeded.count) process(es), \(result.failed.count) failed")
            }
        }
    }

    func terminateSingleInterferingProcess(_ process: MetalHUDProcess, force: Bool = false) {
        runTask(tr("正在关闭 \(process.name)…", "Closing \(process.name)…")) {
            let ok = await self.gamingService.terminateProcess(pid: process.pid, force: force)
            self.scanInterferingProcesses()
            if ok {
                return tr("已关闭 \(process.name)", "Closed \(process.name)")
            } else {
                throw ToolboxError.commandFailed(tr("关闭 \(process.name) 失败", "Failed to close \(process.name)"))
            }
        }
    }

    func increaseCrossOverPriority() {
        runTask(tr("正在检测 CrossOver", "Detecting CrossOver")) {
            let processes = try await self.gamingService.wineProcesses(crossOverOnly: true)
            DiagnosticFileLogger.write("Detected CrossOver process count: \(processes.count)")
            guard !processes.isEmpty else {
                throw ToolboxError.commandFailed(tr("未检测到 CrossOver 或 Wine 进程", "No CrossOver or Wine process found"))
            }
            self.status.phase = .awaitingAuthorization
            try await self.privileged.perform(.renice(processes.map(\.pid)))
            return tr("已提高 \(processes.count) 个进程的优先级", "Updated \(processes.count) processes")
        }
    }

    func loadProcessesForManualSelection() {
        showingProcessSelection = true
        runningProcesses = []
        selectedProcessIDs.removeAll()
        Task {
            do {
                runningProcesses = try await gamingService.runningProcesses().map { process in
                    SystemProcess(
                        pid: process.pid,
                        parentPID: process.parentPID,
                        command: process.command,
                        cpuUsage: process.cpuUsage,
                        applicationPath: NSRunningApplication(processIdentifier: process.pid)?.bundleURL?.path
                    )
                }
            }
            catch { report(error) }
        }
    }

    func increaseSelectedProcessPriority() {
        let identifiers = Array(selectedProcessIDs)
        guard !identifiers.isEmpty else { return }
        showingProcessSelection = false
        runTask(tr("正在提高所选进程优先级", "Increasing selected process priority")) {
            self.status.phase = .awaitingAuthorization
            try await self.privileged.perform(.renice(identifiers))
            return tr("已提高 \(identifiers.count) 个进程的优先级", "Updated \(identifiers.count) selected process(es)")
        }
    }

    func isFavoriteProcess(_ process: SystemProcess) -> Bool {
        configuration.favoriteProcessNames.contains(process.displayName)
    }

    func toggleFavoriteProcess(_ process: SystemProcess) {
        if isFavoriteProcess(process) {
            removeFavoriteProcess(process.displayName)
        } else {
            addFavoriteProcess(process.displayName)
        }
    }

    func addFavoriteProcess(_ name: String) {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !configuration.favoriteProcessNames.contains(normalized),
              configuration.favoriteProcessNames.count < ConfigurationStore.maxFavoriteProcessNames else { return }
        configuration.favoriteProcessNames.append(normalized)
        saveConfiguration()
    }

    func removeFavoriteProcess(_ name: String) {
        configuration.favoriteProcessNames.removeAll { $0 == name }
        saveConfiguration()
    }

    /// Re-applies the app's existing elevated priority to every running
    /// process whose display name matches a saved favorite. Never lowers or
    /// changes the priority level used by the helper.
    func increaseFavoriteProcessPriority() {
        let favoriteNames = configuration.favoriteProcessNames
        guard !favoriteNames.isEmpty else { return }
        showingProcessSelection = false
        runTask(tr("正在优化常用进程", "Optimizing favorite processes")) {
            let processes = try await self.gamingService.runningProcesses()
            let matches = GamingService.matchingFavoriteProcesses(processes, favoriteNames: favoriteNames)
            guard !matches.isEmpty else {
                throw ToolboxError.commandFailed(tr("未检测到收藏的常用进程", "No saved favorite process is running"))
            }
            guard matches.count <= ConfigurationStore.maxFavoriteProcessNames else {
                throw ToolboxError.commandFailed(tr("匹配的常用进程超过 64 个，请编辑常用进程后重试", "More than 64 favorite processes matched; edit favorites and try again"))
            }
            self.status.phase = .awaitingAuthorization
            try await self.privileged.perform(.renice(matches.map(\.pid)))
            return tr("已提高 \(matches.count) 个常用进程的优先级", "Updated \(matches.count) favorite process(es)")
        }
    }

    func setHoYoWaitSeconds(_ seconds: Int) {
        guard [10, 15, 20].contains(seconds) else { return }
        configuration.hoYoWaitSeconds = seconds
        saveConfiguration()
    }

    func setDoesNotRaiseHoYoPriority(_ enabled: Bool) {
        configuration.doesNotRaiseHoYoPriority = enabled
        saveConfiguration()
    }

    func startHoYoAssistant() {
        guard hoyoTask == nil else { return }
        let waitSeconds = configuration.hoYoWaitSeconds
        let doesNotRaisePriority = configuration.doesNotRaiseHoYoPriority
        isHoYoAssistantRunning = true
        status = TaskStatus(phase: .awaitingAuthorization, message: tr("正在启用系统辅助服务", "Enabling system helper"), progress: 0, log: [])
        hoyoTask = Task {
            do {
                try await gamingService.beginHoYoLaunch()
                status.phase = .running
                status.log.append(tr("已写入临时 hosts，等待 \(waitSeconds) 秒", "Temporary hosts applied; waiting \(waitSeconds) seconds"))
                for remaining in stride(from: waitSeconds, through: 1, by: -1) {
                    try Task.checkCancellation()
                    status.message = tr("请启动游戏，剩余 \(remaining) 秒", "Launch the game; \(remaining) seconds remaining")
                    status.progress = Double(waitSeconds - remaining) / Double(waitSeconds)
                    try await Task.sleep(for: .seconds(1))
                }

                try Task.checkCancellation()
                // The opt-out keeps the hosts rewrite+restore path intact and
                // only skips the priority step, so the game's launch handshake
                // is left exactly as macOS scheduled it.
                let processes = try await gamingService.wineProcesses()
                let priorityPIDs = GamingService.hoYoPriorityPIDs(
                    doesNotRaisePriority: doesNotRaisePriority,
                    wineProcesses: processes
                )

                if priorityPIDs == nil {
                    try await gamingService.finishHoYoLaunch()
                    let logs = status.log
                    setTransientStatus(.succeeded, message: tr("倒计时结束，未提升 Wine 进程优先级并已恢复 hosts", "Countdown complete; Wine process priority was unchanged and hosts were restored"))
                    status.log = logs
                    return
                }

                status.message = tr("正在检测 Wine 进程", "Detecting Wine processes")
                status.log.append(tr("等待完成，开始检测 Wine 进程", "Wait complete; detecting Wine processes"))
                DiagnosticFileLogger.write("HoYo Wine check after \(waitSeconds) seconds: \(processes.count) process(es)")
                guard let priorityPIDs, !priorityPIDs.isEmpty else {
                    throw ToolboxError.commandFailed(tr("\(waitSeconds) 秒后未检测到 Wine 进程", "No Wine process detected after \(waitSeconds) seconds"))
                }

                status.phase = .awaitingAuthorization
                try await privileged.perform(.renice(priorityPIDs))
                try await gamingService.finishHoYoLaunch()
                let logs = status.log
                setTransientStatus(.succeeded, message: tr("已优化 \(priorityPIDs.count) 个进程并恢复 hosts", "Updated \(priorityPIDs.count) processes and restored hosts"))
                status.log = logs
            } catch is CancellationError {
                try? await gamingService.finishHoYoLaunch()
                setTransientStatus(.cancelled, message: tr("已取消并恢复 hosts", "Cancelled and restored hosts"))
            } catch {
                try? await gamingService.finishHoYoLaunch()
                report(error)
            }
            hoyoTask = nil
            isHoYoAssistantRunning = false
        }
    }

    func cancelHoYoAssistant() { hoyoTask?.cancel() }

    func loadDisks() {
        showingDiskManager = true
        Task {
            do {
                disks = try await diskService.listEligibleVolumes()
                for preset in configuration.diskPresets { if let path = preset.mountPath { diskPaths[preset.diskIdentifier] = path } }
            } catch { report(error) }
        }
    }

    func choosePath(for diskID: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("选择", "Choose")
        if panel.runModal() == .OK, let url = panel.url { diskPaths[diskID] = url.path }
    }

    func mountSelectedDisks() {
        let assignments = selectedDiskIDs.compactMap { id -> (String, String)? in
            guard let path = diskPaths[id], !path.isEmpty else { return nil }
            return (id, path)
        }
        guard assignments.count == selectedDiskIDs.count, !assignments.isEmpty else {
            report(ToolboxError.invalidPath(tr("请为每个磁盘选择路径", "Choose a path for every volume")))
            return
        }
        runTask(tr("正在挂载磁盘", "Mounting volumes")) {
            for (_, path) in assignments {
                if !FileManager.default.fileExists(atPath: path) { try await self.privileged.perform(.createDirectory(path)) }
            }
            let results = await self.diskService.mountBatch(assignments)
            let failures = results.compactMap { key, result -> String? in if case .failure = result { return key }; return nil }
            guard failures.isEmpty else { throw ToolboxError.commandFailed(tr("挂载失败并已回滚：\(failures.joined(separator: ", "))", "Mount failed and rolled back: \(failures.joined(separator: ", "))")) }
            self.rememberRestorableMounts(assignments)
            return tr("已成功挂载 \(assignments.count) 个卷", "Mounted \(assignments.count) volume(s)")
        }
    }

    func restoreSelectedDisks() {
        runTask(tr("正在恢复默认挂载", "Restoring default mounts")) {
            for identifier in self.selectedDiskIDs { try await self.diskService.restoreDefaultMount(identifier) }
            let selectedUUIDs = Set(self.disks.filter { self.selectedDiskIDs.contains($0.id) }.compactMap(\.volumeUUID))
            self.configuration.restorableDiskMounts.removeAll {
                self.selectedDiskIDs.contains($0.diskIdentifier) || ($0.volumeUUID.map(selectedUUIDs.contains) ?? false)
            }
            self.saveConfiguration()
            return tr("已恢复系统默认挂载路径", "Default mounts restored")
        }
    }

    func saveDiskPreset(_ identifier: String) {
        configuration.diskPresets.removeAll { $0.diskIdentifier == identifier }
        configuration.diskPresets.insert(DiskPreset(diskIdentifier: identifier, mountPath: diskPaths[identifier]), at: 0)
        configuration.diskPresets = Array(configuration.diskPresets.prefix(ConfigurationStore.maxPresets))
        saveConfiguration()
    }

    func deleteDiskPreset(_ identifier: String) {
        configuration.diskPresets.removeAll { $0.diskIdentifier == identifier }
        saveConfiguration()
    }

    func setAutomaticallyRestoreMountsOnLaunch(_ enabled: Bool) {
        configuration.automaticallyRestoreMountsOnLaunch = enabled
        saveConfiguration()
        startAutomaticMountMonitoring()
    }

    func restorePreviousMounts() {
        status = TaskStatus(phase: .running, message: tr("正在恢复上次挂载", "Restoring previous mounts"))
        Task {
            do {
                let availableVolumes = try await diskService.listEligibleVolumes()
                disks = availableVolumes
                enrichRestorableMountUUIDs(from: availableVolumes)
                guard !configuration.restorableDiskMounts.isEmpty else {
                    throw ToolboxError.commandFailed(tr("没有可恢复的挂载记录", "No previous mounts to restore"))
                }
                await restoreMounts(from: availableVolumes, manual: true)
            } catch { report(error) }
        }
    }

    func addDefaultPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = tr("添加", "Add")
        guard panel.runModal() == .OK, let path = panel.url?.path else { return }
        configuration.defaultPaths.removeAll { $0 == path }
        configuration.defaultPaths.insert(path, at: 0)
        configuration.defaultPaths = Array(configuration.defaultPaths.prefix(ConfigurationStore.maxDefaultPaths))
        saveConfiguration()
    }

    func deleteDefaultPath(_ path: String) {
        configuration.defaultPaths.removeAll { $0 == path }
        saveConfiguration()
    }

    func prepareCacheScan() {
        status = TaskStatus(phase: .running, message: tr("正在扫描缓存", "Scanning caches"))
        Task {
            cacheScan = await cacheService.scan(excludingSensitiveFiles: configuration.excludesSensitiveCacheFiles)
            cacheConfirmationStage = 1
            showingCacheConfirmation = true
            status = TaskStatus()
        }
    }

    func confirmCacheCleaning() {
        if cacheConfirmationStage == 1, !configuration.excludesSensitiveCacheFiles {
            cacheConfirmationStage = 2
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showingCacheConfirmation = true }
            return
        }
        // Incomplete scans are surfaced in the alert instead of blocking safe
        // (user-only) cleanup; the risky full cleanup still requires a complete scan.
        guard let scan = cacheScan, scan.inaccessibleTargets.isEmpty || configuration.excludesSensitiveCacheFiles else { return }
        runTask(tr("正在清理缓存", "Cleaning caches")) {
            if !scan.systemTargets.isEmpty { self.status.phase = .awaitingAuthorization }
            let result = try await self.cacheService.clear(scan)
            for failure in result.failedItems {
                DiagnosticFileLogger.write("Cache cleanup failed: \(failure.path.path) - \(failure.reason)")
            }
            if result.failedItems.isEmpty {
                return tr("缓存清理完成，已清理 \(result.removedCount) 项", "Cache cleaning completed; removed \(result.removedCount) item(s)")
            }
            return tr(
                "缓存清理完成，已清理 \(result.removedCount) 项，\(result.failedItems.count) 项无法清理",
                "Cache cleaning completed; removed \(result.removedCount) item(s), \(result.failedItems.count) item(s) could not be removed"
            )
        }
    }

    func openFullDiskAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }

    /// The full (system-touching) cleanup stays blocked while the scan is incomplete,
    /// so the UI can offer Full Disk Access guidance instead of proceeding blindly.
    var isCacheCleanupBlockedByIncompleteScan: Bool {
        guard let scan = cacheScan else { return false }
        return !configuration.excludesSensitiveCacheFiles && !scan.inaccessibleTargets.isEmpty
    }

    func setExcludesSensitiveCacheFiles(_ enabled: Bool) {
        configuration.excludesSensitiveCacheFiles = enabled
        saveConfiguration()
    }

    func toggleSteamDeck() {
        runTask(tr("正在读取设备名称", "Reading hostnames")) {
            let current = try await self.hostnameService.current()
            self.status.phase = .awaitingAuthorization
            if current.computerName == "steamdeck" {
                guard let backup = self.configuration.hostnameBackup else { throw ToolboxError.commandFailed(tr("找不到原始设备名称备份", "Hostname backup is missing")) }
                try await self.hostnameService.restore(backup)
                self.configuration.hostnameBackup = nil
                self.saveConfiguration()
                return tr("已恢复原始设备名称", "Original hostnames restored")
            }
            self.configuration.hostnameBackup = current
            self.saveConfiguration()
            try await self.hostnameService.setSteamDeck()
            return tr("已切换至 SteamDeck 模式", "SteamDeck mode enabled")
        }
    }

    func requestDiagnosticsExport() {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = tr("MetalPilot-诊断-\(Self.diagnosticTimestamp()).txt", "MetalPilot-Diagnostics-\(Self.diagnosticTimestamp()).txt")
        panel.title = tr("导出诊断日志", "Export Diagnostics")
        panel.prompt = tr("导出", "Export")
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        exportDiagnostics(to: destination)
    }

    func repairCoreFeatures() {
        runTask(tr("正在修复核心服务…", "Repairing core features…")) {
            self.status.phase = .awaitingAuthorization
            try await self.privileged.installOrReinstallHelper()
            try await self.privileged.perform(.healthCheck)
            self.checkSystemHealth()
            return tr("核心服务已成功修复", "Core features repaired successfully")
        }
    }

    func exportDiagnostics(to destination: URL) {
        let currentStatus = status
        let currentConfiguration = configuration
        let helperStatus = privileged.diagnosticStatus()
        status = TaskStatus(phase: .running, message: tr("正在收集诊断日志", "Collecting diagnostics"))
        DiagnosticFileLogger.write("Diagnostics export started: \(destination.path)")
        do {
            try (tr("诊断日志正在收集，请稍候…", "Diagnostics collection in progress…") + "\n").write(to: destination, atomically: true, encoding: .utf8)
        } catch {
            report(error)
            return
        }
        Task {
            let diagnosticsText = await diagnosticsService.collect(taskStatus: currentStatus, helperStatus: helperStatus, configuration: currentConfiguration)
            do {
                try diagnosticsText.write(to: destination, atomically: true, encoding: .utf8)
                DiagnosticFileLogger.write("Diagnostics exported: \(destination.path)")
                setTransientStatus(.succeeded, message: tr("诊断日志已导出：\(destination.path)", "Diagnostics exported: \(destination.path)"))
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { report(error) }
        }
    }

    private static func diagnosticTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    // MARK: - System Health Inspector

    func checkSystemHealth() {
        isCheckingHealth = true
        Task {
            let report = await healthInspector.performFullHealthCheck(privileged: privileged)
            self.healthReport = report
            self.isCheckingHealth = false
        }
    }

    func cleanAllLegacyHelpersAndRepair() {
        runTask(tr("正在清理残留并注册服务…", "Cleaning legacy services & registering…")) {
            self.status.phase = .awaitingAuthorization
            try await self.privileged.installOrReinstallHelper()
            try await self.privileged.perform(.healthCheck)
            self.checkSystemHealth()
            return tr("已清理历史残留并成功注册核心服务", "Cleaned legacy residuals and successfully registered core service")
        }
    }

    func openBackgroundSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    private func startAutomaticMountMonitoring() {
        automaticMountTask?.cancel()
        automaticMountTask = nil
        guard configuration.automaticallyRestoreMountsOnLaunch else { return }
        automaticMountTask = Task { [weak self] in
            await self?.monitorDisksAndRestoreMounts()
        }
    }

    private func monitorDisksAndRestoreMounts() async {
        let clock = ContinuousClock()
        let startedAt = clock.now
        var nextLogSecond = 0
        while !Task.isCancelled, configuration.automaticallyRestoreMountsOnLaunch {
            do {
                let availableVolumes = try await diskService.listEligibleVolumes()
                disks = availableVolumes
                enrichRestorableMountUUIDs(from: availableVolumes)
                let elapsedSeconds = Int(startedAt.duration(to: clock.now).components.seconds)
                if elapsedSeconds >= nextLogSecond {
                    let identifiers = availableVolumes.map {
                        "\($0.id)[\($0.volumeUUID ?? "no-uuid")]=\($0.mountPoint ?? "unmounted")"
                    }.joined(separator: ", ")
                    DiagnosticFileLogger.write("Automatic disk scan \(elapsedSeconds)s: \(identifiers.isEmpty ? "no eligible volumes" : identifiers)")
                    nextLogSecond = max(10, ((elapsedSeconds / 10) + 1) * 10)
                }
                if elapsedSeconds >= 10 { await restoreMounts(from: availableVolumes) }
            } catch {
                DiagnosticFileLogger.write("Automatic disk refresh failed: \(error.localizedDescription)")
            }
            do { try await Task.sleep(for: .seconds(1)) }
            catch { return }
        }
    }

    private func restoreMounts(from volumes: [DiskVolume], manual: Bool = false) async {
        let assignments = configuration.restorableDiskMounts.compactMap { preset -> (String, String)? in
            guard let path = preset.mountPath,
                  let volume = DiskService.matchingVolume(for: preset, in: volumes),
                  volume.mountPoint != path,
                  FileManager.default.fileExists(atPath: path) else { return nil }
            return (volume.id, path)
        }
        guard !assignments.isEmpty else {
            if manual {
                report(ToolboxError.commandFailed(tr("没有找到可恢复的磁盘和路径", "No matching volume and path found to restore")))
                return
            }
            if !configuration.restorableDiskMounts.isEmpty {
                DiagnosticFileLogger.write("Automatic mount restore waiting: no matching unmounted target with an existing path")
            }
            return
        }

        status = TaskStatus(phase: .running, message: tr("正在自动恢复上次挂载", "Restoring previous mounts"))
        let results = await diskService.mountBatch(assignments)
        let succeeded = assignments.filter {
            guard case .success? = results[$0.0] else { return false }
            return true
        }
        if succeeded.count == assignments.count {
            rememberRestorableMounts(succeeded)
            DiagnosticFileLogger.write("Automatically restored \(succeeded.count) mount(s)")
            setTransientStatus(.succeeded, message: tr("已自动恢复 \(succeeded.count) 个卷的挂载", "Restored \(succeeded.count) previous mount(s)"))
        } else {
            report(ToolboxError.commandFailed(tr("自动恢复上次挂载失败", "Failed to restore previous mounts")))
        }
    }

    private func rememberRestorableMounts(_ assignments: [(String, String)]) {
        let identifiers = Set(assignments.map(\.0))
        let presets = assignments.map { identifier, path in
            let volume = disks.first { $0.id == identifier }
            return DiskPreset(diskIdentifier: identifier, volumeUUID: volume?.volumeUUID, mountPath: path)
        }
        let volumeUUIDs = Set(presets.compactMap(\.volumeUUID))
        configuration.restorableDiskMounts.removeAll {
            identifiers.contains($0.diskIdentifier) || ($0.volumeUUID.map(volumeUUIDs.contains) ?? false)
        }
        configuration.restorableDiskMounts.insert(contentsOf: presets, at: 0)
        saveConfiguration()
    }

    private func enrichRestorableMountUUIDs(from volumes: [DiskVolume]) {
        var changed = false
        for index in configuration.restorableDiskMounts.indices where configuration.restorableDiskMounts[index].volumeUUID == nil {
            let identifier = configuration.restorableDiskMounts[index].diskIdentifier
            guard let volumeUUID = volumes.first(where: { $0.id == identifier })?.volumeUUID else { continue }
            configuration.restorableDiskMounts[index].volumeUUID = volumeUUID
            changed = true
            DiagnosticFileLogger.write("Added volume UUID to automatic restore record: \(identifier) -> \(volumeUUID)")
        }
        if changed { saveConfiguration() }
    }

    func setLanguagePreference(_ preference: AppLanguagePreference) {
        configuration.languagePreference = preference
        AppLanguage.currentPreference = preference
        saveConfiguration()
        objectWillChange.send()
        DispatchQueue.main.async {
            let localizedTitle = tr("MetalPilot", "MetalPilot", "MetalPilot")
            for window in NSApp.windows where window.canBecomeMain {
                window.title = localizedTitle
            }
        }
    }

    private func saveConfiguration() {
        let value = configuration
        Task { try? await configurationStore.save(value) }
    }

    private func rememberMetalHUDApp(_ applicationURL: URL) {
        let normalizedURL = applicationURL.standardizedFileURL
        let displayName = FileManager.default.displayName(atPath: normalizedURL.path)
        let name = (displayName as NSString).deletingPathExtension
        configuration.recentMetalHUDApps.removeAll { $0.path == normalizedURL.path }
        configuration.recentMetalHUDApps.insert(RecentMetalHUDApp(path: normalizedURL.path, displayName: name), at: 0)
        configuration.recentMetalHUDApps = Array(configuration.recentMetalHUDApps.prefix(ConfigurationStore.maxRecentMetalHUDApps))
        saveConfiguration()
    }

    private func runTask(_ message: String, operation: @escaping @MainActor () async throws -> String) {
        status = TaskStatus(phase: .running, message: message)
        DiagnosticFileLogger.write("Task started: \(message)")
        Task {
            do {
                let result = try await operation()
                DiagnosticFileLogger.write("Task succeeded: \(result)")
                setTransientStatus(.succeeded, message: result)
            } catch is CancellationError {
                setTransientStatus(.cancelled, message: tr("已取消", "Cancelled"))
            } catch { report(error) }
        }
    }

    private func report(_ error: Error) {
        DiagnosticFileLogger.write("Task failed: \(error.localizedDescription)")
        setTransientStatus(error is CancellationError ? .cancelled : .failed, message: error.localizedDescription)
    }

    private var statusClearTask: Task<Void, Never>?

    /// 设置一个终态状态（succeeded/cancelled/failed），并在 5 秒后自动清除为 idle，
    /// 让底部横幅自动消失。若期间发起新任务，旧的清除任务会被取消。
    private func setTransientStatus(_ phase: TaskPhase, message: String, autoClearAfter: TimeInterval = 5) {
        statusClearTask?.cancel()
        status = TaskStatus(phase: phase, message: message, progress: phase == .succeeded ? 1 : nil)
        statusClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(autoClearAfter))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.status = TaskStatus() }
        }
    }

    // MARK: - Gaming Focus Booster (Caffeinate)

    func toggleGamingFocus() {
        Task {
            let active = await focusBooster.isActive
            if active {
                await focusBooster.stop()
                isGamingFocusActive = false
                setTransientStatus(.succeeded, message: tr("已退出游戏专注模式", "Exited gaming focus mode"))
            } else {
                let success = await focusBooster.start()
                isGamingFocusActive = success
                if success {
                    setTransientStatus(.succeeded, message: tr("已开启游戏专注模式 (防休眠/防息屏)", "Gaming focus mode active (sleep & dimming prevented)"))
                } else {
                    setTransientStatus(.failed, message: tr("启动游戏专注模式失败", "Failed to start gaming focus mode"))
                }
            }
        }
    }

    // MARK: - Game Save Finder & Bottle Backup

    func scanBottlesAndSaves() {
        isScanningSaves = true
        Task {
            let bottles = await saveFinderService.discoverBottles()
            discoveredBottles = bottles
            if let current = selectedBottleID, let match = bottles.first(where: { $0.id == current }) {
                bottleGameSaves = await saveFinderService.scanSaveDirectories(in: match)
            } else if let first = bottles.first {
                selectedBottleID = first.id
                bottleGameSaves = await saveFinderService.scanSaveDirectories(in: first)
            } else {
                selectedBottleID = nil
                bottleGameSaves = []
            }
            isScanningSaves = false
        }
    }

    func selectBottle(id: String) {
        selectedBottleID = id
        guard let bottle = discoveredBottles.first(where: { $0.id == id }) else { return }
        isScanningSaves = true
        Task {
            bottleGameSaves = await saveFinderService.scanSaveDirectories(in: bottle)
            isScanningSaves = false
        }
    }

    func revealSaveLocationInFinder(_ location: GameSaveLocation) {
        NSWorkspace.shared.selectFile(location.path, inFileViewerRootedAtPath: (location.path as NSString).deletingLastPathComponent)
    }

    func exportSaveBackup(_ location: GameSaveLocation) {
        let panel = NSSavePanel()
        panel.title = tr("备份游戏存档", "Backup Game Save")
        panel.prompt = tr("备份为 Zip", "Backup as Zip")
        panel.allowedContentTypes = [.zip]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmm"
        panel.nameFieldStringValue = "\(location.gameName)_Save_\(formatter.string(from: Date())).zip"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isBackingUpSave = true
        runTask(tr("正在打包游戏存档…", "Packaging game save…")) {
            try await self.saveFinderService.createBackupArchive(sourceDirectoryPath: location.path, destinationZipPath: url.path)
            self.isBackingUpSave = false
            return tr("已成功备份存档至：\(url.lastPathComponent)", "Saved backup to: \(url.lastPathComponent)")
        }
    }

    // MARK: - Per-App Metal HUD Profiles

    func profileForApp(path: String) -> PerAppMetalHUDProfile? {
        configuration.perAppHUDProfiles.first { $0.appPath == path }
    }

    func saveProfileForApp(path: String, options: MetalHUDOptions) {
        let appName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        if let idx = configuration.perAppHUDProfiles.firstIndex(where: { $0.appPath == path }) {
            configuration.perAppHUDProfiles[idx].options = options
            configuration.perAppHUDProfiles[idx].updatedAt = Date()
        } else {
            configuration.perAppHUDProfiles.append(PerAppMetalHUDProfile(appPath: path, appName: appName, options: options))
        }
        saveConfiguration()
        setTransientStatus(.succeeded, message: tr("已保存 \(appName) 的专属 HUD 配置", "Saved custom HUD profile for \(appName)"))
    }

    func removeProfileForApp(path: String) {
        configuration.perAppHUDProfiles.removeAll { $0.appPath == path }
        saveConfiguration()
        setTransientStatus(.succeeded, message: tr("已恢复默认 HUD 配置", "Restored default HUD profile"))
    }

    func effectiveOptionsForApp(path: String) -> MetalHUDOptions {
        profileForApp(path: path)?.options ?? configuration.metalHUDOptions
    }

    // MARK: - Imported External HUD Presets

    func importedPresetForApp(path: String) -> ImportedHUDPreset? {
        configuration.recentMetalHUDApps.first { $0.path == path }?.importedPreset
    }

    /// Prompts for an external Metal HUD preset file, validates it, copies it into the
    /// managed directory and records it against the app. Invalid files are rejected
    /// before any copy is written, and the failure is reported to the user.
    func importExternalHUDPreset(forAppPath appPath: String) {
        let panel = NSOpenPanel()
        panel.title = tr("选择 Metal HUD 预设文件", "Choose a Metal HUD preset file")
        panel.prompt = tr("导入", "Import")
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.resolvesAliases = true
        if let plist = UTType(filenameExtension: "plist") {
            panel.allowedContentTypes = [plist, .propertyList, .xml]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let appName = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        Task { @MainActor in
            do {
                let imported = try await hudPresetStore.importPreset(from: url, forApplicationPath: appPath)
                if let idx = self.configuration.recentMetalHUDApps.firstIndex(where: { $0.path == appPath }) {
                    // Replace any previously imported preset so we do not orphan its copy.
                    if let previous = self.configuration.recentMetalHUDApps[idx].importedPreset {
                        await self.hudPresetStore.removeManagedPreset(atPath: previous.path)
                    }
                    self.configuration.recentMetalHUDApps[idx].importedPreset = imported
                } else {
                    self.configuration.recentMetalHUDApps.insert(
                        RecentMetalHUDApp(path: appPath, displayName: appName, importedPreset: imported),
                        at: 0
                    )
                }
                self.saveConfiguration()
                self.setTransientStatus(.succeeded, message: tr("已导入 \(appName) 的外部 HUD 预设：\(imported.displayName)", "Imported external HUD preset for \(appName): \(imported.displayName)"))
            } catch {
                self.report(error)
            }
        }
    }

    /// Detaches an imported preset from an app and deletes its managed copy.
    func removeImportedHUDPreset(forAppPath appPath: String) {
        guard let idx = configuration.recentMetalHUDApps.firstIndex(where: { $0.path == appPath }),
              let preset = configuration.recentMetalHUDApps[idx].importedPreset else { return }
        configuration.recentMetalHUDApps[idx].importedPreset = nil
        saveConfiguration()
        cleanManagedPreset(preset)
        let appName = ((appPath as NSString).lastPathComponent as NSString).deletingPathExtension
        setTransientStatus(.succeeded, message: tr("已移除 \(appName) 的外部 HUD 预设，将回退到专属方案/全局预设", "Removed the external HUD preset for \(appName); falling back to the custom/global profile"))
    }

    /// Best-effort managed copy cleanup; failures never surface to the main flow.
    private func cleanManagedPreset(_ preset: ImportedHUDPreset) {
        Task.detached { [hudPresetStore] in
            await hudPresetStore.removeManagedPreset(atPath: preset.path)
        }
    }

    // MARK: - Performance Snapshot Exporter

    func exportPerformanceSnapshot(for appPath: String? = nil) {
        let panel = NSSavePanel()
        panel.title = tr("导出性能诊断快照报告", "Export Performance Snapshot Report")
        panel.prompt = tr("导出报告", "Export Report")
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        panel.nameFieldStringValue = "MetalHUD_PerformanceSnapshot_\(formatter.string(from: Date())).md"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            let opts = appPath.flatMap { self.profileForApp(path: $0)?.options } ?? self.configuration.metalHUDOptions
            let report = await self.snapshotService.generateSnapshotReport(metalHUDOptions: opts, activeApp: appPath)
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
                self.setTransientStatus(.succeeded, message: tr("已成功导出性能快照报告", "Performance snapshot exported"))
                NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
            } catch {
                self.report(error)
            }
        }
    }
}
