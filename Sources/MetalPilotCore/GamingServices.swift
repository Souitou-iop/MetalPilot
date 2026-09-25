import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

public enum PrivilegedOperation: Sendable, Equatable {
    case healthCheck
    case addHoYoHosts
    case removeHoYoHosts
    case renice([Int32])
    case clearSystemCaches
    case setHostnames(HostnameBackup)
    case createDirectory(String)
}

public protocol PrivilegedOperating: Sendable {
    func perform(_ operation: PrivilegedOperation) async throws
}

public actor GamingService {
    public static let hoyoDomains = [
        "globaldp-prod-cn01.bhsr.com", "globaldp-prod-os01.starrails.com",
        "dispatchcnglobal.yuanshen.com", "dispatchosglobal.yuanshen.com",
        "globaldp-prod-cn01.juequling.com", "globaldp-prod-cn02.juequling.com",
        "globaldp-prod-os01.zenlesszonezero.com", "globaldp-prod-os02.zenlesszonezero.com"
    ]

    private let runner: any CommandRunning
    private let privileged: any PrivilegedOperating

    public init(runner: any CommandRunning = ProcessCommandRunner(), privileged: any PrivilegedOperating) {
        self.runner = runner
        self.privileged = privileged
    }

    public func metalHUDEnabled() async -> Bool {
        guard let result = try? await runner.run("/bin/launchctl", arguments: ["getenv", "MTL_HUD_ENABLED"]) else { return false }
        return result.outputString == "1"
    }

    public func metalHUDOptions() async -> MetalHUDOptions {
        func getString(_ key: String) async -> String? {
            let value = (try? await runner.run("/bin/launchctl", arguments: ["getenv", key]).outputString)
            return value.flatMap { $0.isEmpty ? nil : $0 }
        }
        func getDouble(_ key: String) async -> Double? {
            guard let s = await getString(key) else { return nil }
            return Double(s)
        }
        func getInt(_ key: String) async -> Int? {
            guard let s = await getString(key) else { return nil }
            return Int(s)
        }
        func getBool(_ key: String) async -> Bool {
            await getString(key) == "1"
        }
        let opacity = await getDouble("MTL_HUD_OPACITY") ?? 1.0
        let scale = await getDouble("MTL_HUD_SCALE") ?? 0.2
        let alignment = await getString("MTL_HUD_ALIGNMENT") ?? "topright"
        let positionX = await getInt("MTL_HUD_POSITION_X")
        let positionY = await getInt("MTL_HUD_POSITION_Y")
        let elementsRaw = await getString("MTL_HUD_ELEMENTS")
        let elements: [String] = elementsRaw?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []
        let logEnabled = await getBool("MTL_HUD_LOG_ENABLED")
        let shaderLogEnabled = await getBool("MTL_HUD_LOG_SHADER_ENABLED")
        let encoderTimingEnabled = await getBool("MTL_HUD_ENCODER_TIMING_ENABLED")
        let encoderGpuTimelineFrameCount = await getInt("MTL_HUD_ENCODER_GPU_TIMELINE_FRAME_COUNT")
        let encoderGpuTimelineSwapDelta = await getInt("MTL_HUD_ENCODER_GPU_TIMELINE_SWAP_DELTA")
        let showZeroMetrics = await getBool("MTL_HUD_SHOW_ZERO_METRICS")
        let showMetricsRange = await getBool("MTL_HUD_SHOW_METRICS_RANGE")
        let metricTimeout = await getInt("MTL_HUD_METRIC_TIMEOUT")
        let insightsEnabled = await getBool("MTL_HUD_INSIGHTS_ENABLED")
        let insightTimeout = await getInt("MTL_HUD_INSIGHT_TIMEOUT")
        let insightReportInterval = await getInt("MTL_HUD_INSIGHT_REPORT_INTERVAL")
        let rusageUpdateInterval = await getInt("MTL_HUD_RUSAGE_UPDATE_INTERVAL")
        let reportURL = await getString("MTL_HUD_REPORT_URL")
        let disableMenuBar = await getBool("MTL_HUD_DISABLE_MENU_BAR")
        let configFilePath = await getString("MTL_HUD_CONFIG_FILE")
        return MetalHUDOptions(
            opacity: opacity,
            scale: scale,
            alignment: alignment,
            positionX: positionX,
            positionY: positionY,
            elements: elements,
            logEnabled: logEnabled,
            shaderLogEnabled: shaderLogEnabled,
            encoderTimingEnabled: encoderTimingEnabled,
            encoderGpuTimelineFrameCount: encoderGpuTimelineFrameCount,
            encoderGpuTimelineSwapDelta: encoderGpuTimelineSwapDelta,
            showZeroMetrics: showZeroMetrics,
            showMetricsRange: showMetricsRange,
            metricTimeout: metricTimeout,
            insightsEnabled: insightsEnabled,
            insightTimeout: insightTimeout,
            insightReportInterval: insightReportInterval,
            rusageUpdateInterval: rusageUpdateInterval,
            reportURL: reportURL,
            disableMenuBar: disableMenuBar,
            configFilePath: configFilePath
        )
    }

    public func setMetalHUD(enabled: Bool, options: MetalHUDOptions = MetalHUDOptions()) async throws {
        if enabled {
            _ = try await runner.run("/bin/launchctl", arguments: ["setenv", "MTL_HUD_ENABLED", "1"])
            _ = try? await runner.run("/usr/bin/defaults", arguments: ["write", "-g", "MetalForceHudEnabled", "-bool", "YES"])
            let envArgs = Self.metalHUDEnvArgs(for: options)
            let setKeys = Set(envArgs.compactMap { arg -> String? in
                guard let equals = arg.firstIndex(of: "=") else { return nil }
                return String(arg[..<equals])
            })
            for key in Self.allMetalHUDEnvKeys where key != "MTL_HUD_ENABLED" && !setKeys.contains(key) {
                _ = try? await runner.run("/bin/launchctl", arguments: ["unsetenv", key])
            }
            for arg in envArgs {
                guard let equals = arg.firstIndex(of: "=") else { continue }
                let key = String(arg[..<equals])
                let value = String(arg[arg.index(after: equals)...])
                _ = try await runner.run("/bin/launchctl", arguments: ["setenv", key, value])
            }
        } else {
            _ = try? await runner.run("/usr/bin/defaults", arguments: ["delete", "-g", "MetalForceHudEnabled"])
            for key in Self.allMetalHUDEnvKeys {
                _ = try? await runner.run("/bin/launchctl", arguments: ["unsetenv", key])
            }
        }
    }

    public func launchWithMetalHUD(applicationPath: String, options: MetalHUDOptions = MetalHUDOptions()) async throws {
        try await launchWithMetalHUD(
            applicationPath: applicationPath,
            options: options,
            importedPresetPath: nil
        )
    }

    /// Preset-aware launch entry point.
    ///
    /// Priority rule (do not change): when `importedPresetPath` points at an
    /// externally imported preset, that preset's `MTL_HUD_*` values are the *sole*
    /// source of the per-launch HUD environment and `options` is ignored entirely.
    /// When there is no imported preset, `options` (i.e. `AppModel.effectiveOptionsForApp`)
    /// is used exactly as before. The two sources are never merged field by field.
    ///
    /// Without an imported preset, the existing global profile is refreshed first.
    /// With an imported preset, the global profile is left untouched: writing the
    /// per-App/global options here would contradict the preset's launch-scoped
    /// priority and could contaminate unrelated Wine/CrossOver processes.
    /// The final launch keeps the fork's `/usr/bin/open -n -a <app> --env KEY=VALUE` shape.
    public func launchWithMetalHUD(applicationPath: String, options: MetalHUDOptions, importedPresetPath: String?) async throws {
        let applicationURL = URL(fileURLWithPath: applicationPath).standardizedFileURL
        guard applicationURL.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: applicationURL.path) else {
            throw MetalPilotError.invalidPath(applicationPath)
        }

        // Parse (and validate) the imported preset *before* touching launchctl so a
        // broken preset surfaces as a real failure instead of a silent global change.
        let presetEnvironment: [String]?
        if let importedPresetPath {
            presetEnvironment = try Self.metalHUDEnvironment(fromPresetAt: importedPresetPath)
        } else {
            presetEnvironment = nil
        }

        // Refresh the legacy global profile only for profile-based launches.
        // An imported preset must remain launch-scoped; otherwise the old profile
        // can override it for processes that inherit launchctl/defaults values.
        if presetEnvironment == nil {
            try? await setMetalHUD(enabled: true, options: options)
        }

        // Use `open -n -a ... --env ...` to launch a fresh instance with the
        // selected environment rather than reusing an instance without it.
        var arguments = ["-n", "-a", applicationURL.path]
        let envArgs = presetEnvironment ?? Self.metalHUDEnvArgs(for: options, includeEnabled: true)
        for arg in envArgs {
            arguments.append(contentsOf: ["--env", arg])
        }
        _ = try await runner.run("/usr/bin/open", arguments: arguments)
    }

    // MARK: - Imported Metal HUD presets

    /// Parses a Metal HUD preset property list into `KEY=VALUE` environment strings.
    ///
    /// Only `MTL_HUD_`-prefixed keys are kept. Booleans become `1`/`0`, string and
    /// numeric `MTL_HUD_ALIGNMENT` values are translated to the text alignment names,
    /// and any other unsupported value type throws a distinguishable error. The
    /// returned list is always sorted by key and always contains `MTL_HUD_ENABLED=1`.
    public static func metalHUDEnvironment(fromPresetAt presetPath: String) throws -> [String] {
        let presetURL = URL(fileURLWithPath: presetPath)
        guard FileManager.default.fileExists(atPath: presetURL.path),
              !presetURL.hasDirectoryPath else {
            throw MetalPilotError.invalidPath(presetPath)
        }
        guard let data = FileManager.default.contents(atPath: presetURL.path) else {
            throw MetalPilotError.commandFailed(coreText("无法读取 MetalHUD 预设文件：\(presetURL.lastPathComponent)", "Unable to read the MetalHUD preset file: \(presetURL.lastPathComponent)", "MetalHUD プリセットを読み込めません：\(presetURL.lastPathComponent)"))
        }
        let value: Any
        do {
            value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        } catch {
            throw MetalPilotError.malformedOutput(coreText("MetalHUD 预设不是有效的属性列表：\(presetURL.lastPathComponent)", "The MetalHUD preset is not a valid property list: \(presetURL.lastPathComponent)", "MetalHUD プリセットが有効なプロパティリストではありません：\(presetURL.lastPathComponent)"))
        }
        guard let properties = value as? [String: Any] else {
            throw MetalPilotError.malformedOutput(coreText("MetalHUD 预设顶层必须是字典", "The MetalHUD preset must be a dictionary at the top level", "MetalHUD プリセットの最上位は辞書である必要があります"))
        }
        var entries = try properties.keys.sorted().compactMap { key -> String? in
            guard key.hasPrefix("MTL_HUD_") else { return nil }
            guard let text = metalHUDValue(properties[key], for: key) else {
                throw MetalPilotError.malformedOutput(coreText("MetalHUD 预设包含不支持的值：\(key)", "The MetalHUD preset contains an unsupported value: \(key)", "MetalHUD プリセットに未対応の値があります：\(key)"))
            }
            return "\(key)=\(text)"
        }
        // A preset always turns the HUD on for the launch it is attached to.
        if !entries.contains(where: { $0.hasPrefix("MTL_HUD_ENABLED=") }) {
            entries.insert("MTL_HUD_ENABLED=1", at: 0)
        }
        return entries
    }

    private static func metalHUDValue(_ value: Any?, for key: String) -> String? {
        if let string = value as? String {
            if key == "MTL_HUD_ALIGNMENT", let number = Int(string) {
                return legacyAlignmentName(number) ?? string
            }
            return string
        }
        guard let number = value as? NSNumber else { return nil }
        if key == "MTL_HUD_ALIGNMENT", let alignment = legacyAlignmentName(number.intValue) {
            return alignment
        }
        if CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue ? "1" : "0"
        }
        return number.stringValue
    }

    private static func legacyAlignmentName(_ value: Int) -> String? {
        [
            10: "topleft", 11: "topcenter", 12: "topright",
            14: "centerleft", 15: "centered", 16: "centerright",
            18: "bottomleft", 19: "bottomcenter", 20: "bottomright"
        ][value]
    }

    private static let allMetalHUDEnvKeys: [String] = [
        "MTL_HUD_ENABLED",
        "MTL_HUD_OPACITY",
        "MTL_HUD_SCALE",
        "MTL_HUD_ALIGNMENT",
        "MTL_HUD_POSITION_X",
        "MTL_HUD_POSITION_Y",
        "MTL_HUD_ELEMENTS",
        "MTL_HUD_LOG_ENABLED",
        "MTL_HUD_LOG_SHADER_ENABLED",
        "MTL_HUD_ENCODER_TIMING_ENABLED",
        "MTL_HUD_ENCODER_GPU_TIMELINE_FRAME_COUNT",
        "MTL_HUD_ENCODER_GPU_TIMELINE_SWAP_DELTA",
        "MTL_HUD_SHOW_ZERO_METRICS",
        "MTL_HUD_SHOW_METRICS_RANGE",
        "MTL_HUD_METRIC_TIMEOUT",
        "MTL_HUD_INSIGHTS_ENABLED",
        "MTL_HUD_INSIGHT_TIMEOUT",
        "MTL_HUD_INSIGHT_REPORT_INTERVAL",
        "MTL_HUD_RUSAGE_UPDATE_INTERVAL",
        "MTL_HUD_REPORT_URL",
        "MTL_HUD_DISABLE_MENU_BAR",
        "MTL_HUD_CONFIG_FILE"
    ]

    public static func metalHUDEnvArgs(for options: MetalHUDOptions, includeEnabled: Bool = false) -> [String] {
        var args: [String] = []
        if includeEnabled {
            args.append("MTL_HUD_ENABLED=1")
        }
        args.append("MTL_HUD_OPACITY=\(String(format: "%g", options.opacity))")
        args.append("MTL_HUD_SCALE=\(String(format: "%g", options.scale))")
        args.append("MTL_HUD_ALIGNMENT=\(options.alignment.lowercased())")
        if let v = options.positionX {
            args.append("MTL_HUD_POSITION_X=\(v)")
        }
        if let v = options.positionY {
            args.append("MTL_HUD_POSITION_Y=\(v)")
        }
        if !options.elements.isEmpty {
            args.append("MTL_HUD_ELEMENTS=\(options.elements.joined(separator: ","))")
        }
        if options.logEnabled {
            args.append("MTL_HUD_LOG_ENABLED=1")
        }
        if options.shaderLogEnabled {
            args.append("MTL_HUD_LOG_SHADER_ENABLED=1")
        }
        if options.encoderTimingEnabled {
            args.append("MTL_HUD_ENCODER_TIMING_ENABLED=1")
        }
        if let v = options.encoderGpuTimelineFrameCount {
            args.append("MTL_HUD_ENCODER_GPU_TIMELINE_FRAME_COUNT=\(v)")
        }
        if let v = options.encoderGpuTimelineSwapDelta {
            args.append("MTL_HUD_ENCODER_GPU_TIMELINE_SWAP_DELTA=\(v)")
        }
        if options.showZeroMetrics {
            args.append("MTL_HUD_SHOW_ZERO_METRICS=1")
        }
        if options.showMetricsRange {
            args.append("MTL_HUD_SHOW_METRICS_RANGE=1")
        }
        if let v = options.metricTimeout {
            args.append("MTL_HUD_METRIC_TIMEOUT=\(v)")
        }
        if options.insightsEnabled {
            args.append("MTL_HUD_INSIGHTS_ENABLED=1")
        }
        if let v = options.insightTimeout {
            args.append("MTL_HUD_INSIGHT_TIMEOUT=\(v)")
        }
        if let v = options.insightReportInterval {
            args.append("MTL_HUD_INSIGHT_REPORT_INTERVAL=\(v)")
        }
        if let v = options.rusageUpdateInterval {
            args.append("MTL_HUD_RUSAGE_UPDATE_INTERVAL=\(v)")
        }
        if let s = options.reportURL, !s.isEmpty {
            args.append("MTL_HUD_REPORT_URL=\(s)")
        }
        if options.disableMenuBar {
            args.append("MTL_HUD_DISABLE_MENU_BAR=1")
        }
        if let s = options.configFilePath, !s.isEmpty {
            args.append("MTL_HUD_CONFIG_FILE=\(s)")
        }
        return args
    }

    // MARK: - iOS device control (xcrun devicectl)

    /// Hard cap on how many extra launch arguments may be handed to devicectl.
    /// Keeps a runaway UI state from turning into an unbounded command line.
    public static let maxIOSLaunchArgumentCount = 32

    /// Reads Xcode's CoreDevice inventory. Read-only: it never talks to a device.
    ///
    /// Devices whose hardware platform is not iOS/iPadOS are dropped, so a Mac,
    /// Apple TV or Apple Watch that CoreDevice happens to list can never be
    /// presented as a launchable "iPhone/iPad".
    public func iosDevices() async throws -> [IOSDevice] {
        let result = try await Self.runDevicectl(runner: runner, arguments: ["devicectl", "list", "devices", "--json-output", "-"])
        return try Self.parseIOSDevices(result.outputString)
    }

    /// Lists the apps CoreDevice can see on one selected iOS device.
    public func iosApps(on deviceID: String) async throws -> [IOSInstalledApp] {
        guard Self.isIOSDeviceIdentifier(deviceID) else { throw MetalPilotError.invalidPath(deviceID) }
        let result = try await Self.runDevicectl(
            runner: runner,
            arguments: ["devicectl", "device", "info", "apps", "--include-all-apps", "--device", deviceID, "--json-output", "-"]
        )
        return try Self.parseIOSApps(result.outputString)
    }

    /// Launches one app on a connected iOS device with a process-scoped Metal HUD
    /// environment, optionally followed by extra app launch arguments.
    ///
    /// Deliberately scoped and small for this first version:
    /// - never routed through the privileged helper, and never persisted;
    /// - `--terminate-existing` is always passed, so an already-running instance
    ///   of the target app is terminated (unsaved progress may be lost). Callers
    ///   must warn the user before invoking this;
    /// - a successful `devicectl` exit only proves the command was accepted, not
    ///   that the HUD was actually drawn by the app.
    public func launchIOSAppWithMetalHUD(
        deviceID: String,
        bundleIdentifier: String,
        launchArguments: [String] = []
    ) async throws {
        guard Self.isIOSDeviceIdentifier(deviceID) else { throw MetalPilotError.invalidPath(deviceID) }
        guard Self.isIOSBundleIdentifier(bundleIdentifier) else { throw MetalPilotError.invalidPath(bundleIdentifier) }
        try Self.validateIOSLaunchArguments(launchArguments)

        var arguments = [
            "devicectl", "device", "process", "launch",
            "--device", deviceID,
            "--environment-variables", #"{"MTL_HUD_ENABLED":"1"}"#,
            "--terminate-existing",
            bundleIdentifier
        ]
        // Each extra argument is forwarded as its own argv entry after a single
        // "--" separator; nothing is joined into a shell string.
        if !launchArguments.isEmpty {
            arguments.append("--")
            arguments.append(contentsOf: launchArguments)
        }
        _ = try await Self.runDevicectl(runner: runner, arguments: arguments)
    }

    /// Parses `devicectl list devices --json-output -`.
    public static func parseIOSDevices(_ text: String) throws -> [IOSDevice] {
        let rows = try jsonRows(text, arrayKeys: ["devices"])
        var seen = Set<String>()
        return rows.compactMap { row -> IOSDevice? in
            // Platform gate first: anything that is not clearly iOS/iPadOS is dropped.
            guard isIOSPlatform(row) else { return nil }
            guard let identifier = string(in: row, keys: ["identifier", "udid", "deviceIdentifier"]),
                  isIOSDeviceIdentifier(identifier),
                  seen.insert(identifier).inserted else { return nil }
            // Use schema-specific paths. A recursive "find any name" lookup is
            // unsafe here because real devicectl rows also contain capability,
            // CPU, and OS-build dictionaries with unrelated `name`/`state` keys.
            let name = string(at: [
                ["name"], ["deviceName"],
                ["properties", "state", "name"],
                ["deviceProperties", "name"]
            ], in: row) ?? identifier
            return IOSDevice(
                id: identifier,
                name: name,
                model: string(at: [
                    ["properties", "hardware", "productType"],
                    ["hardwareProperties", "productType"],
                    ["properties", "hardware", "modelName"],
                    ["deviceProperties", "modelName"],
                    ["modelName"], ["model"]
                ], in: row) ?? "",
                osVersion: string(at: [
                    ["properties", "software", "osVersionNumber", "stringValue"],
                    ["properties", "software", "osVersionNumber"],
                    ["deviceProperties", "osVersionNumber", "stringValue"],
                    ["deviceProperties", "osVersionNumber"],
                    ["properties", "software", "osVersion"], ["osVersion"]
                ], in: row) ?? "",
                state: string(at: [
                    ["properties", "connection", "state"],
                    ["properties", "state", "bootState"],
                    ["deviceProperties", "bootState"],
                    ["connectionState"], ["state"]
                ], in: row) ?? ""
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Parses `devicectl device info apps --json-output -`.
    public static func parseIOSApps(_ text: String) throws -> [IOSInstalledApp] {
        let rows = try jsonRows(text, arrayKeys: ["apps", "applications"])
        var seen = Set<String>()
        return rows.compactMap { row -> IOSInstalledApp? in
            guard let bundleIdentifier = string(in: row, keys: ["bundleIdentifier", "bundleID"]),
                  isIOSBundleIdentifier(bundleIdentifier),
                  seen.insert(bundleIdentifier).inserted else { return nil }
            return IOSInstalledApp(
                bundleIdentifier: bundleIdentifier,
                displayName: string(in: row, keys: ["displayName", "name"]) ?? bundleIdentifier,
                version: string(in: row, keys: ["shortVersion", "version", "CFBundleShortVersionString"]) ?? ""
            )
        }
        .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Rejects argument lists that would be ambiguous or unrepresentable on a
    /// command line: NUL and newline terminators, plus an overall count cap.
    public static func validateIOSLaunchArguments(_ arguments: [String]) throws {
        guard arguments.count <= maxIOSLaunchArgumentCount else {
            throw MetalPilotError.invalidPath(coreText(
                "iOS 启动参数过多（最多 \(maxIOSLaunchArgumentCount) 个）",
                "Too many iOS launch arguments (max \(maxIOSLaunchArgumentCount))",
                "iOS 起動引数が多すぎます（最大 \(maxIOSLaunchArgumentCount) 個）"
            ))
        }
        for argument in arguments where argument.contains("\0") || argument.contains("\n") || argument.contains("\r") {
            throw MetalPilotError.invalidPath(coreText(
                "iOS 启动参数不能包含空字符或换行",
                "iOS launch arguments cannot contain NUL or newline characters",
                "iOS 起動引数に NUL や改行は使用できません"
            ))
        }
    }

    /// Runs devicectl through `/usr/bin/xcrun` and turns the two "toolchain is
    /// not usable" failures into actionable messages instead of raw exit codes.
    private static func runDevicectl(runner: any CommandRunning, arguments: [String]) async throws -> CommandResult {
        do {
            return try await runner.run("/usr/bin/xcrun", arguments: arguments)
        } catch let error as MetalPilotError {
            throw mapDevicectlError(error)
        } catch {
            throw error
        }
    }

    private static func mapDevicectlError(_ error: MetalPilotError) -> Error {
        guard case .commandFailed(let message) = error else { return error }
        let lowered = message.lowercased()
        if lowered.contains("not a developer tool") || lowered.contains("unable to find utility")
            || lowered.contains("xcrun: error") || lowered.contains("requires xcode") {
            return MetalPilotError.commandFailed(coreText(
                "未找到可用的 Xcode 工具链。请安装完整版 Xcode，并用 xcode-select --switch 将其设为活动开发者目录。",
                "No usable Xcode toolchain was found. Install the full Xcode and select it with xcode-select --switch.",
                "利用可能な Xcode ツールチェーンが見つかりません。完全版 Xcode をインストールし、xcode-select --switch で選択してください。"
            ))
        }
        if lowered.contains("error 1000") || lowered.contains("specified device was not found") {
            return MetalPilotError.commandFailed(coreText(
                "未找到该设备。请确认设备已连接、已信任本机并在 Xcode 中完成配对。",
                "The device could not be found. Confirm it is connected, trusted, and paired in Xcode.",
                "デバイスが見つかりません。接続・信頼・Xcode でのペアリングを確認してください。"
            ))
        }
        return error
    }

    /// True only when a raw devicectl device row clearly describes an iPhone/iPad.
    ///
    /// The platform/deviceType values are read with nested lookups because
    /// `devicectl` has moved hardware fields between `hardwareProperties`,
    /// `deviceProperties` and the newer `properties` dictionary.
    private static func isIOSPlatform(_ row: [String: Any]) -> Bool {
        let platform = string(at: [
            ["properties", "hardware", "platform"],
            ["hardwareProperties", "platform"], ["platform"]
        ], in: row)?.lowercased()
        let deviceType = string(at: [
            ["properties", "hardware", "deviceType"],
            ["hardwareProperties", "deviceType"], ["deviceType"]
        ], in: row)?.lowercased()

        if let platform {
            // Accept "iOS", "iPadOS" and combined values such as "iOS, iPadOS".
            // NOTE: `"ipados".contains("ios")` is false, so iPadOS must be matched
            // explicitly rather than by a naive `contains("ios")` check.
            let mentionsAppleMobileOS = platform.contains("ios") || platform.contains("ipados")
            guard mentionsAppleMobileOS else { return false }
            // Reject values that also name a different Apple platform, e.g. a
            // hypothetical "macOS/iOS bridge" or "iOS, tvOS".
            let mentionsOtherAppleOS = platform.contains("macos")
                || platform.contains("tvos")
                || platform.contains("watchos")
                || platform.contains("visionos")
            guard !mentionsOtherAppleOS else { return false }
        }

        if let deviceType {
            // iPadOS devices still report deviceType "iPad", so accept both.
            let isMobileDevice = deviceType.contains("iphone") || deviceType.contains("ipad")
            guard isMobileDevice else { return false }
        }

        // Require at least one positive iOS signal so unrelated rows never qualify.
        return platform != nil || deviceType != nil
    }

    private static func jsonRows(_ text: String, arrayKeys: Set<String>) throws -> [[String: Any]] {
        guard let data = text.data(using: .utf8) else {
            throw MetalPilotError.malformedOutput(coreText("无法读取 devicectl 输出", "Unable to read devicectl output", "devicectl の出力を読み込めません"))
        }
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw MetalPilotError.malformedOutput(coreText("devicectl 没有返回可识别的 JSON", "devicectl did not return valid JSON", "devicectl が有効な JSON を返しませんでした"))
        }
        var rows: [[String: Any]] = []
        func visit(_ value: Any) {
            if let dictionary = value as? [String: Any] {
                for (key, nested) in dictionary where arrayKeys.contains(key) {
                    if let items = nested as? [Any] {
                        rows.append(contentsOf: items.compactMap { $0 as? [String: Any] })
                    }
                }
                dictionary.values.forEach(visit)
            } else if let array = value as? [Any] {
                array.forEach(visit)
            }
        }
        visit(root)
        return rows
    }

    private static func string(at paths: [[String]], in object: [String: Any]) -> String? {
        for path in paths {
            var current: Any = object
            var matched = true
            for key in path {
                guard let dictionary = current as? [String: Any], let next = dictionary[key] else {
                    matched = false
                    break
                }
                current = next
            }
            guard matched else { continue }
            if let value = current as? String, !value.isEmpty { return value }
            if let number = current as? NSNumber { return number.stringValue }
        }
        return nil
    }

    private static func string(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let match = string(in: nested, keys: keys) { return match }
        }
        return nil
    }

    private static func isIOSDeviceIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 255 && !value.contains("\0") && !value.contains("\n") && !value.contains("\r")
    }

    private static func isIOSBundleIdentifier(_ value: String) -> Bool {
        value.count <= 255
            && value.range(of: #"^[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil
    }

    public func detectMetalHUDInterferingProcesses(recentAppPaths: [String] = []) async throws -> [MetalHUDProcess] {
        let result = try await runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,command="])
        let processes = Self.parseProcessTable(result.outputString)
        return Self.identifyInterferingProcesses(processes, recentAppPaths: recentAppPaths)
    }

    public func terminateProcesses(pids: [Int32], force: Bool = false) async -> (succeeded: [Int32], failed: [Int32]) {
        var succeeded: [Int32] = []
        var failed: [Int32] = []
        for pid in pids {
            let ok = await terminateProcess(pid: pid, force: force)
            if ok {
                succeeded.append(pid)
            } else {
                failed.append(pid)
            }
        }
        return (succeeded, failed)
    }

    public func terminateProcess(pid: Int32, force: Bool = false) async -> Bool {
        guard pid > 1 else { return false }
        if let app = NSRunningApplication(processIdentifier: pid) {
            if force {
                _ = app.forceTerminate()
            } else {
                _ = app.terminate()
            }
        }
        let sigArg = force ? "-9" : "-15"
        let res = try? await runner.run("/bin/kill", arguments: [sigArg, String(pid)])
        return res?.exitCode == 0 || NSRunningApplication(processIdentifier: pid) == nil
    }

    public func wineProcesses(crossOverOnly: Bool = false) async throws -> [(pid: Int32, command: String)] {
        let result = try await runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,command="])
        return Self.matchingProcesses(Self.parseProcessTable(result.outputString), crossOverOnly: crossOverOnly)
            .map { ($0.pid, $0.command) }
    }

    public func runningProcesses() async throws -> [SystemProcess] {
        let result = try await runner.run("/bin/ps", arguments: ["-axo", "pid=,ppid=,%cpu=,command="])
        return Self.sortedRunningProcesses(Self.parseProcessTable(result.outputString)
            .filter { $0.pid > 1 && !$0.command.lowercased().contains("macgametoolbox") }
        )
    }

    /// The single decision that separates "hosts only" from "hosts + priority"
    /// for the HoYo launch assistant. It deliberately returns `nil` instead of
    /// a PID list when the user opted out, so the caller cannot accidentally
    /// race a renice against the game's anti-cheat handshake.
    public static func hoYoPriorityPIDs(
        doesNotRaisePriority: Bool,
        wineProcesses: [(pid: Int32, command: String)]
    ) -> [Int32]? {
        guard !doesNotRaisePriority else { return nil }
        return wineProcesses.map(\.pid)
    }

    public func increasePriority(crossOverOnly: Bool = true) async throws -> Int {
        let processes = try await wineProcesses(crossOverOnly: crossOverOnly)
        guard !processes.isEmpty else { throw MetalPilotError.commandFailed(coreText("未检测到 Wine 进程", "No Wine process found")) }
        try await privileged.perform(.renice(processes.map(\.pid)))
        return processes.count
    }

    public func beginHoYoLaunch() async throws {
        try await privileged.perform(.addHoYoHosts)
    }

    public func finishHoYoLaunch() async throws {
        try await privileged.perform(.removeHoYoHosts)
    }

    public func cleanStaleHoYoEntries() async {
        try? await privileged.perform(.removeHoYoHosts)
    }

    public static func parseProcessTable(_ text: String) -> [SystemProcess] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 3, let pid = Int32(fields[0]), let parentPID = Int32(fields[1]) else { return nil }
            // Older callers still pass `pid=,ppid=,command=`; only treat the
            // fourth field as CPU percent when it actually parses as a number.
            guard fields.count == 4 else {
                return SystemProcess(pid: pid, parentPID: parentPID, command: String(fields[2]))
            }
            let cpuUsage = Double(fields[2]).flatMap { $0.isFinite ? $0 : nil } ?? 0
            return SystemProcess(pid: pid, parentPID: parentPID, command: String(fields[3]), cpuUsage: cpuUsage)
        }
    }

    /// Highest CPU first, then case-insensitive command, then PID so the order
    /// stays stable when several processes report identical usage.
    public static func sortedRunningProcesses(_ processes: [SystemProcess]) -> [SystemProcess] {
        processes.sorted {
            if $0.cpuUsage != $1.cpuUsage { return $0.cpuUsage > $1.cpuUsage }
            let commandOrder = $0.command.localizedStandardCompare($1.command)
            if commandOrder != .orderedSame { return commandOrder == .orderedAscending }
            return $0.pid < $1.pid
        }
    }

    /// Favorite optimisation matches exact, case-sensitive display names so a
    /// saved favorite never widens to a look-alike process.
    public static func matchingFavoriteProcesses(_ processes: [SystemProcess], favoriteNames: [String]) -> [SystemProcess] {
        let names = Set(favoriteNames)
        return processes.filter { names.contains($0.displayName) }
    }

    public static func matchingProcesses(_ processes: [SystemProcess], crossOverOnly: Bool) -> [SystemProcess] {
        let roots = Set(processes.filter {
            let value = $0.command.lowercased()
            return value.contains("crossover.app/contents/macos/crossover") || value.hasSuffix("/crossover")
        }.map(\.pid))
        var descendants = roots
        var addedDescendant = true
        while addedDescendant {
            addedDescendant = false
            for process in processes where descendants.contains(process.parentPID) && !descendants.contains(process.pid) {
                descendants.insert(process.pid)
                addedDescendant = true
            }
        }
        return processes.filter { process in
            let value = process.command.lowercased()
            guard !value.contains("macgametoolbox") else { return false }
            let isWine = value.contains("wine") || value.contains("wineserver") || value.contains("winedevice")
            if !crossOverOnly { return isWine }
            // Wine services commonly detach from CrossOver and are re-parented to
            // launchd. If the CrossOver root has exited, retain Wine detection.
            return roots.isEmpty ? isWine : descendants.contains(process.pid) || (value.contains("crossover") && isWine)
        }
    }

    public static func identifyInterferingProcesses(
        _ processes: [SystemProcess],
        recentAppPaths: [String] = []
    ) -> [MetalHUDProcess] {
        let recentNormalized = Set(recentAppPaths.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })

        let ignoredSubstrings = [
            "macgametoolbox",
            "/system/library/",
            "/usr/libexec/",
            "/usr/sbin/",
            "/usr/bin/",
            "windowserver",
            "dock.app",
            "finder.app",
            "systemsettings.app",
            "safari.app",
            "google chrome.app",
            "xcode.app",
            "terminal.app",
            "iterm.app",
            "visual studio code.app",
            "trae.app",
            "cursor.app",
            "antigravity"
        ]

        var results: [MetalHUDProcess] = []

        for p in processes {
            guard p.pid > 1 else { continue }
            let cmdLower = p.command.lowercased()

            if cmdLower.contains("macgametoolbox") { continue }
            if ignoredSubstrings.contains(where: { cmdLower.contains($0) }) {
                let isWine = cmdLower.contains("wineserver") || cmdLower.contains("wine64") || cmdLower.contains("winedevice")
                let isKnownLauncher = cmdLower.contains("steam") || cmdLower.contains("crossover") || cmdLower.contains("whisky")
                if !isWine && !isKnownLauncher {
                    continue
                }
            }

            if let wine = matchWineRuntime(p) {
                results.append(wine)
                continue
            }

            if let launcher = matchLauncher(p) {
                results.append(launcher)
                continue
            }

            if let game = matchGameOrApp(p, recentPaths: recentNormalized) {
                results.append(game)
                continue
            }
        }

        return results.sorted {
            if $0.category != $1.category {
                return $0.category.rawValue < $1.category.rawValue
            }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public static func extractAppBundlePath(from command: String) -> String? {
        let pattern = #"(/(?:Applications|Users|Volumes)/[^\s"]+?\.app)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: command, options: [], range: NSRange(location: 0, length: command.utf16.count)),
              let range = Range(match.range(at: 1), in: command) else {
            return nil
        }
        return String(command[range])
    }

    private static func matchLauncher(_ p: SystemProcess) -> MetalHUDProcess? {
        let cmd = p.command
        let cmdLower = cmd.lowercased()

        struct LauncherPattern {
            let matches: (String) -> Bool
            let name: String
            let fallbackBundle: String?
        }

        let patterns: [LauncherPattern] = [
            LauncherPattern(matches: { $0.contains("steam.app") || $0.contains("steam_osx") || $0.hasSuffix("/steam") }, name: "Steam", fallbackBundle: "/Applications/Steam.app"),
            LauncherPattern(matches: { $0.contains("crossover.app") || $0.contains("/crossover") || $0.contains("cxoffice") }, name: "CrossOver", fallbackBundle: "/Applications/CrossOver.app"),
            LauncherPattern(matches: { $0.contains("whisky.app") || $0.contains("/whisky") }, name: "Whisky", fallbackBundle: "/Applications/Whisky.app"),
            LauncherPattern(matches: { $0.contains("heroic.app") || $0.contains("/heroic") }, name: "Heroic Games Launcher", fallbackBundle: "/Applications/Heroic.app"),
            LauncherPattern(matches: { $0.contains("battle.net.app") || $0.contains("battle.net") || $0.contains("agent.app") }, name: "Battle.net", fallbackBundle: "/Applications/Battle.net.app"),
            LauncherPattern(matches: { $0.contains("epic games launcher.app") || $0.contains("epicgameslauncher") }, name: "Epic Games Launcher", fallbackBundle: "/Applications/Epic Games Launcher.app"),
            LauncherPattern(matches: { $0.contains("gog galaxy.app") || $0.contains("galaxyclient") }, name: "GOG Galaxy", fallbackBundle: "/Applications/GOG Galaxy.app"),
            LauncherPattern(matches: { $0.contains("porting kit.app") || $0.contains("portingkit") }, name: "Porting Kit", fallbackBundle: "/Applications/Porting Kit.app"),
            LauncherPattern(matches: { $0.contains("origin.app") || $0.contains("eadesktop") }, name: "EA / Origin", fallbackBundle: "/Applications/Origin.app"),
            LauncherPattern(matches: { $0.contains("playcover.app") }, name: "PlayCover", fallbackBundle: "/Applications/PlayCover.app"),
            LauncherPattern(matches: { $0.contains("ryujinx.app") || $0.contains("/ryujinx") }, name: "Ryujinx", fallbackBundle: "/Applications/Ryujinx.app"),
            LauncherPattern(matches: { $0.contains("rpcs3.app") || $0.contains("/rpcs3") }, name: "RPCS3", fallbackBundle: "/Applications/RPCS3.app"),
            LauncherPattern(matches: { $0.contains("dolphin.app") || $0.contains("/dolphin") }, name: "Dolphin", fallbackBundle: "/Applications/Dolphin.app"),
            LauncherPattern(matches: { $0.contains("pcsx2.app") || $0.contains("/pcsx2") }, name: "PCSX2", fallbackBundle: "/Applications/PCSX2.app")
        ]

        for pat in patterns {
            if pat.matches(cmdLower) {
                let bundle = extractAppBundlePath(from: cmd) ?? pat.fallbackBundle
                return MetalHUDProcess(
                    pid: p.pid,
                    parentPID: p.parentPID,
                    name: pat.name,
                    command: p.command,
                    category: .launcher,
                    appBundlePath: bundle,
                    reasonZh: "启动器常驻后台会导致从其启动的游戏子进程继承旧的环境变量，建议重启启动器。",
                    reasonEn: "Launcher running in background causes child game processes to inherit stale environment variables."
                )
            }
        }
        return nil
    }

    private static func matchWineRuntime(_ p: SystemProcess) -> MetalHUDProcess? {
        let cmd = p.command
        let cmdLower = cmd.lowercased()

        let wineKeywords = [
            "wineserver", "wine64-preloader", "wine-preloader", "wine64",
            "winedevice.exe", "winedevice", "explorer.exe", "services.exe",
            "plugplay.exe", "conhost.exe"
        ]

        for kw in wineKeywords {
            if cmdLower.contains(kw) {
                let fileName = cmd.split(separator: "/").last.map(String.init) ?? kw
                let bundle = extractAppBundlePath(from: cmd)
                return MetalHUDProcess(
                    pid: p.pid,
                    parentPID: p.parentPID,
                    name: fileName.isEmpty ? kw : fileName,
                    command: p.command,
                    category: .wineRuntime,
                    appBundlePath: bundle,
                    reasonZh: "Wine 容器与后台服务持有旧的环境状态，关闭后重启游戏可使新配置生效。",
                    reasonEn: "Wine runtime services hold previous environment states. Closing them resets the bottle environment."
                )
            }
        }
        return nil
    }

    private static func matchGameOrApp(_ p: SystemProcess, recentPaths: Set<String>) -> MetalHUDProcess? {
        let cmd = p.command
        let cmdLower = cmd.lowercased()

        // 1. Matches user-recorded recent MetalHUD apps
        for path in recentPaths {
            if !path.isEmpty && cmdLower.contains(path) {
                let displayName = FileManager.default.displayName(atPath: path)
                let name = (displayName as NSString).deletingPathExtension
                return MetalHUDProcess(
                    pid: p.pid,
                    parentPID: p.parentPID,
                    name: name.isEmpty ? "Game (\(p.pid))" : name,
                    command: p.command,
                    category: .gameOrApp,
                    appBundlePath: path,
                    reasonZh: "游戏在启动时已锁定 Metal 渲染配置，关闭后重新启动即可应用最新的 HUD 样式。",
                    reasonEn: "The game locked its Metal rendering configuration on launch. Restart it to apply the new HUD style."
                )
            }
        }

        // 2. Matches steamapps/common or drive_c games or cxbottle
        if cmdLower.contains("steamapps/common") || cmdLower.contains("drive_c") || cmdLower.contains("cxbottle") {
            let bundle = extractAppBundlePath(from: cmd)
            let rawName = bundle.flatMap { ($0 as NSString).lastPathComponent } ?? cmd.split(separator: "/").last.map(String.init) ?? "Game"
            let name = (rawName as NSString).deletingPathExtension
            return MetalHUDProcess(
                pid: p.pid,
                parentPID: p.parentPID,
                name: name.isEmpty ? "Game (\(p.pid))" : name,
                command: p.command,
                category: .gameOrApp,
                appBundlePath: bundle,
                reasonZh: "游戏在启动时已锁定 Metal 渲染配置，关闭后重新启动即可应用最新的 HUD 样式。",
                reasonEn: "The game locked its Metal rendering configuration on launch. Restart it to apply the new HUD style."
            )
        }

        // 3. Check if running inside an .app under /Applications or ~/Applications
        if let bundle = extractAppBundlePath(from: cmd) {
            let bundleLower = bundle.lowercased()
            if bundleLower.contains("/applications/") {
                let rawName = (bundle as NSString).lastPathComponent
                let name = (rawName as NSString).deletingPathExtension
                return MetalHUDProcess(
                    pid: p.pid,
                    parentPID: p.parentPID,
                    name: name.isEmpty ? "App (\(p.pid))" : name,
                    command: p.command,
                    category: .gameOrApp,
                    appBundlePath: bundle,
                    reasonZh: "应用在启动时已锁定 Metal 渲染配置，关闭后重新启动即可应用最新的 HUD 样式。",
                    reasonEn: "The app locked its Metal rendering configuration on launch. Restart it to apply the new HUD style."
                )
            }
        }

        return nil
    }
}

public actor HostnameService {
    private let runner: any CommandRunning
    private let privileged: any PrivilegedOperating

    public init(runner: any CommandRunning = ProcessCommandRunner(), privileged: any PrivilegedOperating) {
        self.runner = runner
        self.privileged = privileged
    }

    public func current() async throws -> HostnameBackup {
        let computer = try await read("ComputerName")
        let local = (try? await read("LocalHostName")) ?? Self.slug(computer)
        let host = (try? await read("HostName")) ?? local
        return HostnameBackup(computerName: computer, hostName: host, localHostName: local)
    }

    public func setSteamDeck() async throws {
        try await privileged.perform(.setHostnames(HostnameBackup(computerName: "steamdeck", hostName: "steamdeck", localHostName: "steamdeck")))
    }

    public func restore(_ backup: HostnameBackup) async throws {
        try await privileged.perform(.setHostnames(backup))
    }

    private func read(_ key: String) async throws -> String {
        try await runner.run("/usr/sbin/scutil", arguments: ["--get", key]).outputString
    }

    private static func slug(_ value: String) -> String {
        let mapped = value.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." ? $0 : "-" }
        return String(mapped).trimmingCharacters(in: CharacterSet(charactersIn: "-."))
    }
}

// MARK: - Game Save Finder & Bottle Backup Service

public actor GameSaveFinderService {
    private let fileManager: FileManager
    private let runner: any CommandRunning

    public init(fileManager: FileManager = .default, runner: any CommandRunning = ProcessCommandRunner()) {
        self.fileManager = fileManager
        self.runner = runner
    }

    public func discoverBottles() async -> [WineBottle] {
        var bottles: [WineBottle] = []
        let home = fileManager.homeDirectoryForCurrentUser.path

        // 1. CrossOver Bottles
        let crossOverPath = (home as NSString).appendingPathComponent("Library/Application Support/CrossOver/Bottles")
        bottles.append(contentsOf: scanBottleDirectory(at: crossOverPath, type: .crossover))

        // 2. Whisky Bottles
        let whiskyPath = (home as NSString).appendingPathComponent("Library/Application Support/com.isaacmarovitz.Whisky/Bottles")
        bottles.append(contentsOf: scanBottleDirectory(at: whiskyPath, type: .whisky))

        // 3. Heroic Bottles
        let heroicPaths = [
            (home as NSString).appendingPathComponent("Library/Application Support/heroic/prefixes"),
            (home as NSString).appendingPathComponent("Games/Heroic/Prefixes")
        ]
        for hp in heroicPaths {
            bottles.append(contentsOf: scanBottleDirectory(at: hp, type: .heroic))
        }

        // 4. Default Wine Prefix (~/.wine)
        let defaultWinePath = (home as NSString).appendingPathComponent(".wine")
        if fileManager.fileExists(atPath: (defaultWinePath as NSString).appendingPathComponent("drive_c")) {
            bottles.append(WineBottle(name: "Default Wine (~/.wine)", type: .customWine, path: defaultWinePath))
        }

        return bottles
    }

    private func scanBottleDirectory(at basePath: String, type: WineBottleType) -> [WineBottle] {
        guard let items = try? fileManager.contentsOfDirectory(atPath: basePath) else { return [] }
        var result: [WineBottle] = []
        for item in items {
            let fullPath = (basePath as NSString).appendingPathComponent(item)
            let driveC = (fullPath as NSString).appendingPathComponent("drive_c")
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: driveC, isDirectory: &isDir), isDir.boolValue {
                result.append(WineBottle(name: item, type: type, path: fullPath))
            }
        }
        return result
    }

    public func scanSaveDirectories(in bottle: WineBottle) async -> [GameSaveLocation] {
        var saves: [GameSaveLocation] = []
        let driveC = (bottle.path as NSString).appendingPathComponent("drive_c")
        let usersPath = (driveC as NSString).appendingPathComponent("users")
        guard let userDirs = try? fileManager.contentsOfDirectory(atPath: usersPath) else { return [] }

        // Directories to ignore (system/empty standard dirs)
        let ignoredDirs: Set<String> = [
            "microsoft", "temp", "crossover", "public", "all users", "default", "default user",
            "crashdumps", "package cache", "d3dmetal", "dxvk", "nvidia", "amd", "intel",
            "cefdialog", "iconcache.db", "thumbs.db", "desktop.ini", "logs", "cache"
        ]

        for userDir in userDirs {
            let userRoot = (usersPath as NSString).appendingPathComponent(userDir)

            // 1. AppData/Local & AppData/Roaming & AppData/LocalLow
            let appDataCandidates = [
                ("AppData/Local", (userRoot as NSString).appendingPathComponent("AppData/Local")),
                ("AppData/LocalLow", (userRoot as NSString).appendingPathComponent("AppData/LocalLow")),
                ("AppData/Roaming", (userRoot as NSString).appendingPathComponent("AppData/Roaming")),
                ("Local Settings/Application Data", (userRoot as NSString).appendingPathComponent("Local Settings/Application Data"))
            ]
            for (cat, catPath) in appDataCandidates {
                if let gameDirs = try? fileManager.contentsOfDirectory(atPath: catPath) {
                    for gd in gameDirs {
                        if ignoredDirs.contains(gd.lowercased()) || gd.hasPrefix(".") { continue }
                        let full = (catPath as NSString).appendingPathComponent(gd)
                        if let loc = buildSaveLocation(bottleName: bottle.name, gameName: gd, category: cat, path: full) {
                            saves.append(loc)
                        }
                    }
                }
            }

            // 2. Saved Games
            let savedGamesPath = (userRoot as NSString).appendingPathComponent("Saved Games")
            if let gameDirs = try? fileManager.contentsOfDirectory(atPath: savedGamesPath) {
                for gd in gameDirs {
                    if ignoredDirs.contains(gd.lowercased()) || gd.hasPrefix(".") { continue }
                    let full = (savedGamesPath as NSString).appendingPathComponent(gd)
                    if let loc = buildSaveLocation(bottleName: bottle.name, gameName: gd, category: "Saved Games", path: full) {
                        saves.append(loc)
                    }
                }
            }

            // 3. Documents & Documents/My Games
            let myGamesPath = (userRoot as NSString).appendingPathComponent("Documents/My Games")
            if let gameDirs = try? fileManager.contentsOfDirectory(atPath: myGamesPath) {
                for gd in gameDirs {
                    if ignoredDirs.contains(gd.lowercased()) || gd.hasPrefix(".") { continue }
                    let full = (myGamesPath as NSString).appendingPathComponent(gd)
                    if let loc = buildSaveLocation(bottleName: bottle.name, gameName: gd, category: "Documents/My Games", path: full) {
                        saves.append(loc)
                    }
                }
            }
        }

        // Sort by last modified date (newest first)
        return saves.sorted { $0.lastModified > $1.lastModified }
    }

    private func buildSaveLocation(bottleName: String, gameName: String, category: String, path: String) -> GameSaveLocation? {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { return nil }
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        let modDate = attrs[.modificationDate] as? Date ?? Date()
        let sizeFormatted = formatDirectorySize(at: path)
        return GameSaveLocation(
            bottleName: bottleName,
            gameName: gameName,
            category: category,
            path: path,
            sizeFormatted: sizeFormatted,
            lastModified: modDate
        )
    }

    private func formatDirectorySize(at path: String) -> String {
        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
            return "0 KB"
        }
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]), let size = resourceValues.fileSize {
                totalBytes += Int64(size)
            }
        }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }

    public func createBackupArchive(sourceDirectoryPath: String, destinationZipPath: String) async throws {
        // Use ditto -c -k to create clean macOS-compatible zip archives
        let result = try await runner.run("/usr/bin/ditto", arguments: ["-c", "-k", "--sequesterRsrc", sourceDirectoryPath, destinationZipPath])
        if result.exitCode != 0 {
            throw MetalPilotError.commandFailed(result.errorString.isEmpty ? "Zip backup failed" : result.errorString)
        }
    }
}

// MARK: - Gaming Focus Booster (Caffeinate Manager)

public actor GamingFocusBooster {
    private var caffeinateProcess: Process?

    public init() {}

    public var isActive: Bool {
        caffeinateProcess?.isRunning ?? false
    }

    public func start() -> Bool {
        if isActive { return true }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -d: prevent display from sleeping
        // -i: prevent system from idle sleeping
        // -m: prevent disk from idle sleeping
        p.arguments = ["-d", "-i", "-m"]
        do {
            try p.run()
            caffeinateProcess = p
            return true
        } catch {
            return false
        }
    }

    public func stop() {
        if let p = caffeinateProcess, p.isRunning {
            p.terminate()
        }
        caffeinateProcess = nil
    }

    deinit {
        if let p = caffeinateProcess, p.isRunning {
            p.terminate()
        }
    }
}

// MARK: - Performance Snapshot Service

public actor PerformanceSnapshotService {
    private let runner: any CommandRunning

    public init(runner: any CommandRunning = ProcessCommandRunner()) {
        self.runner = runner
    }

    public func generateSnapshotReport(metalHUDOptions: MetalHUDOptions, activeApp: String? = nil) async -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let dateStr = formatter.string(from: now)

        var report = """
        # MetalPilot - 性能诊断快照报告 (Performance Snapshot)
        **生成时间**：\(dateStr)
        **目标应用**：\(activeApp ?? "全局环境 (Global Environment)")

        ---

        ## 1. 硬件与系统环境
        - **macOS 版本**：\(ProcessInfo.processInfo.operatingSystemVersionString)
        - **芯片架构**：Apple Silicon (\(ProcessInfo.processInfo.activeProcessorCount) Cores)
        - **物理内存**：\(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) GB

        ---

        ## 2. Metal HUD 调优参数
        - **全局注入开关**：已开启 (MTL_HUD_ENABLED=1)
        - **渲染缩放比例**：\(String(format: "%.2f", metalHUDOptions.scale))
        - **图层不透明度**：\(Int(metalHUDOptions.opacity * 100))%
        - **屏幕方位**：\(metalHUDOptions.alignment)
        - **激活监控指标项 (\(metalHUDOptions.elements.count))**：\(metalHUDOptions.elements.isEmpty ? "全部默认指标" : metalHUDOptions.elements.joined(separator: ", "))
        - **着色器编译日志**：\(metalHUDOptions.shaderLogEnabled ? "已启用" : "未启用")
        - **编码器耗时追踪**：\(metalHUDOptions.encoderTimingEnabled ? "已启用" : "未启用")

        ---

        ## 3. 运行中的游戏与 Wine 兼容层进程
        """

        if let psResult = try? await runner.run("/bin/ps", arguments: ["-ax", "-o", "pid,ppid,command"]) {
            let lines = psResult.outputString.components(separatedBy: .newlines)
            let filtered = lines.filter { line in
                let l = line.lowercased()
                return l.contains("wine") || l.contains("crossover") || l.contains("whisky") || l.contains("steam") || l.contains("d3dmetal") || l.contains("game")
            }
            if filtered.isEmpty {
                report += "\n- 未检测到运行中的 Wine / 游戏进程。\n"
            } else {
                report += "\n```text\n"
                for l in filtered.prefix(15) {
                    report += "\(l)\n"
                }
                report += "```\n"
            }
        }

        report += """

        ---
        *由 MetalPilot 自动生成。可直接附于社区讨论或技术支持工单。*
        """
        return report
    }
}

// MARK: - System Health Inspector

public actor SystemHealthInspector {
    private let runner: any CommandRunning
    private let fileManager: FileManager

    public init(runner: any CommandRunning = ProcessCommandRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.fileManager = fileManager
    }

    public func performFullHealthCheck(privileged: (any PrivilegedOperating)?) async -> SystemHealthReport {
        var items: [HealthCheckItem] = []
        var legacyFound: [String] = []

        // 1. Privileged Helper Check (Passive & Read-only, no authorization prompt)
        let helperPath = "/Library/PrivilegedHelperTools/metalpilot.helper"
        let plistPath = "/Library/LaunchDaemons/metalpilot.helper.plist"
        let helperExists = fileManager.fileExists(atPath: helperPath)
        let plistExists = fileManager.fileExists(atPath: plistPath)

        if helperExists && plistExists {
            items.append(HealthCheckItem(
                nameZh: "特权辅助服务 (Privileged Helper)",
                nameEn: "Privileged Helper Service",
                nameJa: "特権ヘルパーサービス",
                status: .healthy,
                detailZh: "辅助服务已安装就绪 (metalpilot.helper)。",
                detailEn: "Helper service is installed and ready (metalpilot.helper).",
                detailJa: "ヘルパーサービスが正常にインストールされています (metalpilot.helper)。"
            ))
        } else {
            items.append(HealthCheckItem(
                nameZh: "特权辅助服务 (Privileged Helper)",
                nameEn: "Privileged Helper Service",
                nameJa: "特権ヘルパーサービス",
                status: .healthy,
                detailZh: "未安装（按需使用：首次使用修改 hosts、挂载磁盘或调整优先级等提权功能时再授权，或手动点击下方安装）。",
                detailEn: "Not installed (On-demand: will prompt on first privileged feature or manual install).",
                detailJa: "未インストール（オンデマンド：特権機能の初回実行時または手動ボタンでインストールできます）。"
            ))
        }

        // 2. Legacy Helper Residuals Check
        let legacyNames = ["macgametoolbox.helper", "com.iven.macgametoolbox.helper", "com.iven.macgametoolbox.helper.v9", "com.iven.macgametoolbox.helper.v8", "com.iven.macgametoolbox.helper.v7", "com.iven.macgametoolbox.helper.v6", "com.iven.macgametoolbox.helper.v5", "com.iven.macgametoolbox.helper.v4", "com.iven.macgametoolbox.helper.v3"]
        for legacy in legacyNames {
            let legacyP = "/Library/LaunchDaemons/\(legacy).plist"
            let legacyT = "/Library/PrivilegedHelperTools/\(legacy)"
            if fileManager.fileExists(atPath: legacyP) || fileManager.fileExists(atPath: legacyT) {
                legacyFound.append(legacy)
            }
        }

        // 3. Screen Recording Permission Check (For Frame Gen & Scaling) - 100% Passive & Non-intrusive
        let screenCaptureGranted = CGPreflightScreenCaptureAccess()
        if screenCaptureGranted {
            items.append(HealthCheckItem(
                nameZh: "屏幕录制权限 (超分与补帧)",
                nameEn: "Screen Recording Access (Scaling & FG)",
                nameJa: "画面収録権限（超解像・補フレーム）",
                status: .healthy,
                detailZh: "屏幕录制权限已授予，可正常使用游戏超分辨率与零延迟补帧。",
                detailEn: "Screen recording permission granted for zero-latency frame generation and upscaling.",
                detailJa: "画面収録権限が許可されており、超解像スケーリングと補フレームが利用可能です。"
            ))
        } else {
            items.append(HealthCheckItem(
                nameZh: "屏幕录制权限 (超分与补帧)",
                nameEn: "Screen Recording Access (Scaling & FG)",
                nameJa: "画面収録権限（超解像・補フレーム）",
                status: .warning,
                detailZh: "未授予（按需授权：仅在开启画质超分与补帧功能时需要，首次启动该功能时将自动引导授权）。",
                detailEn: "Not granted (On-demand: only required when enabling Scaling & Frame Gen).",
                detailJa: "未許可（オンデマンド：超解像・補フレーム機能の有効化時のみ必要、初回起動時に案内されます）。"
            ))
        }

        // 4. Accessibility Permission Check (For Synthetic Cursor & Mouse Constraint) - 100% Passive
        let accessibilityGranted = AXIsProcessTrusted()
        if accessibilityGranted {
            items.append(HealthCheckItem(
                nameZh: "辅助功能权限 (光标锁定与约束)",
                nameEn: "Accessibility Access (Mouse Lock)",
                nameJa: "アクセシビリティ権限（マウス拘束）",
                status: .healthy,
                detailZh: "辅助功能权限已授予，可支持游戏内鼠标光标拘束锁定与合成硬件光标。",
                detailEn: "Accessibility permission granted for mouse constraint and synthetic cursor.",
                detailJa: "アクセシビリティ権限が許可されており、ゲーム内マウス拘束と合成カーソルが利用可能です。"
            ))
        } else {
            items.append(HealthCheckItem(
                nameZh: "辅助功能权限 (光标锁定与约束)",
                nameEn: "Accessibility Access (Mouse Lock)",
                nameJa: "アクセシビリティ権限（マウス拘束）",
                status: .warning,
                detailZh: "未授予（按需授权：仅在开启 ⌘⇧C 游戏光标锁定与约束时需要）。",
                detailEn: "Not granted (On-demand: only required for ⌘⇧C mouse locking).",
                detailJa: "未許可（オンデマンド：⌘⇧C によるマウス拘束機能の利用時のみ必要）。"
            ))
        }

        // 5. Metal HUD Environment Check
        let hudEnvResult = try? await runner.run("/bin/launchctl", arguments: ["getenv", "MTL_HUD_ENABLED"])
        let hudActive = hudEnvResult?.outputString == "1"
        items.append(HealthCheckItem(
            nameZh: "Metal HUD 注入环境",
            nameEn: "Metal HUD Hook Environment",
            nameJa: "Metal HUD 環境変数",
            status: .healthy,
            detailZh: hudActive ? "全局 HUD 变量已注入 (MTL_HUD_ENABLED=1)。" : "全局 HUD 变量就绪（当前处于关闭状态）。",
            detailEn: hudActive ? "Global HUD variable active (MTL_HUD_ENABLED=1)." : "Global HUD variable ready (currently off).",
            detailJa: hudActive ? "グローバル HUD 変数が有効化されています (MTL_HUD_ENABLED=1)。" : "HUD 環境変数は待機状態です（現在は無効）。"
        ))

        // 6. Storage & Cache Access Check
        let cachesPath = fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches").path
        let cachesWritable = fileManager.isWritableFile(atPath: cachesPath)
        items.append(HealthCheckItem(
            nameZh: "缓存与本地存储访问权限",
            nameEn: "Storage & Cache Directory Access",
            status: cachesWritable ? .healthy : .error,
            detailZh: cachesWritable ? "用户缓存目录具备完整读写权限。" : "用户缓存目录读写权限受限。",
            detailEn: cachesWritable ? "User cache directory is fully accessible." : "User cache directory access is restricted."
        ))

        return SystemHealthReport(items: items, legacyHelpersFound: legacyFound, checkedAt: Date())
    }
}



/// Owns imported Metal HUD preset files so a per-app preset stays available even
/// if the user's original export is moved or deleted.
///
/// Deliberately named `ManagedHUDPresetStore` instead of upstream's
/// `MetalHUDPresetStore`, and it lives alongside the fork's existing core types
/// instead of adding a new Core source file to the Xcode project.
public actor ManagedHUDPresetStore {
    private let directoryURL: URL
    private let fileManager: FileManager

    public init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("com.iven.macgametoolbox", isDirectory: true)
            self.directoryURL = support.appendingPathComponent("MetalHUDPresets", isDirectory: true)
        }
    }

    public var managedDirectoryURL: URL { directoryURL }

    /// Validates `sourceURL` as a Metal HUD preset, then copies it into the managed
    /// directory under a stable, collision-free name.
    ///
    /// Validation happens *before* the copy, so an unreadable or malformed file
    /// never leaves a managed copy behind.
    public func importPreset(from sourceURL: URL, forApplicationPath applicationPath: String) throws -> ImportedHUDPreset {
        let source = sourceURL.standardizedFileURL
        guard fileManager.fileExists(atPath: source.path), !source.hasDirectoryPath else {
            throw MetalPilotError.invalidPath(source.path)
        }
        // Parse first: a broken preset must not create a managed copy.
        _ = try GamingService.metalHUDEnvironment(fromPresetAt: source.path)

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let suffix = source.pathExtension.isEmpty ? "plist" : source.pathExtension
        let destination = uniqueDestination(forApplicationPath: applicationPath, suffix: suffix)
        try fileManager.copyItem(at: source, to: destination)
        return ImportedHUDPreset(
            path: destination.path,
            displayName: source.deletingPathExtension().lastPathComponent,
            importedAt: Date()
        )
    }

    /// Removes a managed copy previously returned by `importPreset`.
    ///
    /// Cleanup is best-effort and never throws: a missing file or a failed delete
    /// must not crash the caller's removal flow.
    public func removeManagedPreset(atPath path: String) {
        guard !path.isEmpty else { return }
        let target = URL(fileURLWithPath: path).standardizedFileURL
        // Only ever touch files that actually live in our managed directory.
        guard target.deletingLastPathComponent().standardizedFileURL.path == directoryURL.standardizedFileURL.path else { return }
        try? fileManager.removeItem(at: target)
    }

    private func uniqueDestination(forApplicationPath applicationPath: String, suffix: String) -> URL {
        let base = stableName(for: applicationPath)
        var candidate = directoryURL
            .appendingPathComponent("\(base)-\(UUID().uuidString)")
            .appendingPathExtension(suffix)
        var attempt = 0
        while fileManager.fileExists(atPath: candidate.path), attempt < 8 {
            candidate = directoryURL
                .appendingPathComponent("\(base)-\(UUID().uuidString)")
                .appendingPathExtension(suffix)
            attempt += 1
        }
        return candidate
    }

    private func stableName(for applicationPath: String) -> String {
        let candidate = URL(fileURLWithPath: applicationPath).deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let result = candidate.unicodeScalars.map { allowed.contains($0) ? String($0) : "-" }.joined()
        return result.isEmpty ? "MetalHUD" : result
    }
}
