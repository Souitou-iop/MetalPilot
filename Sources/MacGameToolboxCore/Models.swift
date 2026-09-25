import Foundation

public func coreText(_ chinese: String, _ english: String, _ japanese: String? = nil) -> String {
    guard let preferred = Locale.preferredLanguages.first else { return english }
    let code = Locale(identifier: preferred).language.languageCode?.identifier ?? "en"
    if code.hasPrefix("zh") { return chinese }
    if code.hasPrefix("ja") { return japanese ?? english }
    return english
}

public enum AppLanguagePreference: String, Codable, CaseIterable, Sendable {
    case system = "system"
    case chinese = "zh-Hans"
    case english = "en"
    case japanese = "ja"

    public var displayName: String {
        switch self {
        case .system: return "System Default"
        case .chinese: return "简体中文"
        case .english: return "English"
        case .japanese: return "日本語"
        }
    }
}

public enum TaskPhase: String, Codable, Sendable {
    case idle, awaitingAuthorization, running, succeeded, failed, cancelled
}

public struct TaskStatus: Equatable, Sendable {
    public var phase: TaskPhase
    public var message: String
    public var progress: Double?
    public var log: [String]

    public init(phase: TaskPhase = .idle, message: String = "", progress: Double? = nil, log: [String] = []) {
        self.phase = phase
        self.message = message
        self.progress = progress
        self.log = log
    }
}

public struct DiskVolume: Identifiable, Hashable, Sendable {
    public let id: String
    public let volumeUUID: String?
    public let name: String
    public let fileSystem: String
    public let mountPoint: String?
    public let size: UInt64
    public let wholeDisk: String
    public let isInternal: Bool

    public init(id: String, volumeUUID: String? = nil, name: String, fileSystem: String, mountPoint: String?, size: UInt64, wholeDisk: String, isInternal: Bool) {
        self.id = id
        self.volumeUUID = volumeUUID
        self.name = name
        self.fileSystem = fileSystem
        self.mountPoint = mountPoint
        self.size = size
        self.wholeDisk = wholeDisk
        self.isInternal = isInternal
    }
}

public struct DiskPreset: Codable, Hashable, Sendable {
    public var diskIdentifier: String
    public var volumeUUID: String?
    public var mountPath: String?

    public init(diskIdentifier: String, volumeUUID: String? = nil, mountPath: String? = nil) {
        self.diskIdentifier = diskIdentifier
        self.volumeUUID = volumeUUID
        self.mountPath = mountPath
    }
}

public struct HostnameBackup: Codable, Equatable, Sendable {
    public var computerName: String
    public var hostName: String
    public var localHostName: String

    public init(computerName: String, hostName: String, localHostName: String) {
        self.computerName = computerName
        self.hostName = hostName
        self.localHostName = localHostName
    }
}

public struct SystemProcess: Identifiable, Hashable, Sendable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let parentPID: Int32
    public let command: String
    public let cpuUsage: Double
    public let applicationPath: String?

    public init(pid: Int32, parentPID: Int32, command: String, cpuUsage: Double = 0, applicationPath: String? = nil) {
        self.pid = pid
        self.parentPID = parentPID
        self.command = command
        self.cpuUsage = cpuUsage
        self.applicationPath = applicationPath
    }

    /// Best-known location for display and search: an explicit application
    /// path, then an `.app` bundle embedded in the command, then the
    /// executable's directory.
    public var locationPath: String? {
        applicationPath ?? Self.appBundlePath(in: command) ?? executableDirectory
    }

    /// Matches a free-text query against the command, the resolved location,
    /// or the PID so the process picker can search by name, directory or PID.
    public func matches(searchText: String) -> Bool {
        command.localizedCaseInsensitiveContains(searchText)
            || locationPath?.localizedCaseInsensitiveContains(searchText) == true
            || String(pid).contains(searchText)
    }

    public func matchesFavoriteName(_ name: String) -> Bool {
        displayName == name
    }

    /// Executable name, preferring the binary inside an `.app` bundle so
    /// `/Applications/Foo.app/Contents/MacOS/Foo -flag` reports `Foo`.
    public var displayName: String {
        if let contentsRange = command.range(of: "/Contents/MacOS/") {
            let executable = command[contentsRange.upperBound...].split(whereSeparator: \.isWhitespace).first
            if let executable, !executable.isEmpty { return String(executable) }
        }
        let executable = command.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? command
        return URL(fileURLWithPath: executable).lastPathComponent
    }

    private var executableDirectory: String? {
        guard let executable = command.split(whereSeparator: \.isWhitespace).first,
              executable.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: String(executable)).deletingLastPathComponent().path
    }

    /// Extracts the first path segment that sits inside an `.app` bundle and
    /// stops before the next slash, so trailing arguments are not captured.
    private static func appBundlePath(in command: String) -> String? {
        let expression = try? NSRegularExpression(pattern: #"(?:^|\s)(/.*?\.app)(?=/|$)"#)
        let range = NSRange(command.startIndex..., in: command)
        guard let match = expression?.firstMatch(in: command, range: range),
              let bundleRange = Range(match.range(at: 1), in: command) else { return nil }
        return String(command[bundleRange])
    }
}

public enum MetalHUDProcessCategory: String, Codable, Hashable, CaseIterable, Sendable {
    case launcher
    case wineRuntime
    case gameOrApp

    public var titleZh: String {
        switch self {
        case .launcher: return "游戏平台与启动器"
        case .wineRuntime: return "Wine 与兼容层服务"
        case .gameOrApp: return "运行中的游戏与应用"
        }
    }

    public var titleEn: String {
        switch self {
        case .launcher: return "Game Launchers & Platforms"
        case .wineRuntime: return "Wine & Runtime Services"
        case .gameOrApp: return "Running Games & Apps"
        }
    }

    public var iconName: String {
        switch self {
        case .launcher: return "arrow.triangle.2.circlepath.circle.fill"
        case .wineRuntime: return "gearshape.2.fill"
        case .gameOrApp: return "gamecontroller.fill"
        }
    }
}

public struct MetalHUDProcess: Identifiable, Hashable, Sendable, Codable {
    public var id: Int32 { pid }
    public let pid: Int32
    public let parentPID: Int32
    public let name: String
    public let command: String
    public let category: MetalHUDProcessCategory
    public let appBundlePath: String?
    public let reasonZh: String
    public let reasonEn: String

    public init(
        pid: Int32,
        parentPID: Int32,
        name: String,
        command: String,
        category: MetalHUDProcessCategory,
        appBundlePath: String? = nil,
        reasonZh: String,
        reasonEn: String
    ) {
        self.pid = pid
        self.parentPID = parentPID
        self.name = name
        self.command = command
        self.category = category
        self.appBundlePath = appBundlePath
        self.reasonZh = reasonZh
        self.reasonEn = reasonEn
    }
}

public struct RecentMetalHUDApp: Codable, Hashable, Identifiable, Sendable {
    public var path: String
    public var displayName: String
    /// Optional externally imported Metal HUD preset (plist) associated with this app.
    /// Schema 3 configurations written before this feature have no key here, so the
    /// property is optional and decoded with `decodeIfPresent`.
    public var importedPreset: ImportedHUDPreset?
    public var id: String { path }

    public init(path: String, displayName: String, importedPreset: ImportedHUDPreset? = nil) {
        self.path = path
        self.displayName = displayName
        self.importedPreset = importedPreset
    }

    private enum CodingKeys: String, CodingKey {
        case path, displayName, importedPreset
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        displayName = try container.decode(String.self, forKey: .displayName)
        importedPreset = try container.decodeIfPresent(ImportedHUDPreset.self, forKey: .importedPreset)
    }
}

/// A Metal HUD preset (property list) the user imported from an external file.
///
/// Named `ImportedHUDPreset` on purpose: the app target already owns an unrelated
/// `MetalHUDPreset` enum used for the built-in UI presets (minimal/balanced/complex),
/// so this type must never reuse that name.
public struct ImportedHUDPreset: Codable, Hashable, Sendable {
    /// Absolute path to the managed copy inside Application Support (not the user's original export).
    public var path: String
    /// User-facing name, derived from the imported file name.
    public var displayName: String
    public var importedAt: Date?

    public init(path: String, displayName: String, importedAt: Date? = nil) {
        self.path = path
        self.displayName = displayName
        self.importedAt = importedAt
    }
}

public struct MetalHUDElement: Sendable, Equatable {
    public let raw: String
    public let zh: String
    public let en: String
    public let ja: String
    public let unitOrSampleZh: String
    public let unitOrSampleEn: String
    public let unitOrSampleJa: String
    public let hintZh: String
    public let hintEn: String

    public init(
        raw: String,
        zh: String,
        en: String,
        ja: String = "",
        unitOrSampleZh: String = "",
        unitOrSampleEn: String = "",
        unitOrSampleJa: String = "",
        hintZh: String,
        hintEn: String
    ) {
        self.raw = raw
        self.zh = zh
        self.en = en
        self.ja = ja.isEmpty ? en : ja
        self.unitOrSampleZh = unitOrSampleZh
        self.unitOrSampleEn = unitOrSampleEn
        self.unitOrSampleJa = unitOrSampleJa.isEmpty ? unitOrSampleEn : unitOrSampleJa
        self.hintZh = hintZh
        self.hintEn = hintEn
    }

    public static let allElements: [MetalHUDElement] = [
        MetalHUDElement(raw: "device", zh: "设备", en: "Device", ja: "デバイス",
                        unitOrSampleZh: "示例: Apple M2 Pro", unitOrSampleEn: "e.g. Apple M2 Pro", unitOrSampleJa: "例: Apple M2 Pro",
                        hintZh: "显示当前使用的 Metal 设备名称。", hintEn: "Shows the name of the active MTLDevice."),
        MetalHUDElement(raw: "rosetta", zh: "Rosetta 信息", en: "Rosetta Info", ja: "Rosetta 情報",
                        unitOrSampleZh: "示例: x86_64", unitOrSampleEn: "e.g. x86_64", unitOrSampleJa: "例: x86_64",
                        hintZh: "当 App 通过 Rosetta 转译运行时，显示活跃架构 (x86_64)。", hintEn: "Shows the active architecture (x86_64) if the app runs through the Rosetta translation layer."),
        MetalHUDElement(raw: "layersize", zh: "图层尺寸与合成", en: "Layer Size & Composition", ja: "レイヤー解像度・合成",
                        unitOrSampleZh: "示例: 2560×1440 (Direct)", unitOrSampleEn: "e.g. 2560×1440 (Direct)", unitOrSampleJa: "例: 2560×1440 (Direct)",
                        hintZh: "显示图层尺寸与呈现模式（直接或合成）。", hintEn: "Shows the size of the layer and the present mode (direct or composited)."),
        MetalHUDElement(raw: "layerscale", zh: "图层缩放与像素格式", en: "Layer Scale & Pixel Format", ja: "スケール・ピクセル形式",
                        unitOrSampleZh: "示例: 2.0x (BGRA8Unorm)", unitOrSampleEn: "e.g. 2.0x (BGRA8Unorm)", unitOrSampleJa: "例: 2.0x (BGRA8Unorm)",
                        hintZh: "显示图层内容缩放因子与像素格式。", hintEn: "Shows the content scale factor and pixel format of the layer."),
        MetalHUDElement(raw: "memory", zh: "内存", en: "Memory", ja: "メモリ使用量",
                        unitOrSampleZh: "单位: MB / GB (如 3.4 GB)", unitOrSampleEn: "Unit: MB / GB (e.g. 3.4 GB)", unitOrSampleJa: "単位: MB / GB (例: 3.4 GB)",
                        hintZh: "显示进程当前内存使用量与 MTLDevice 的 currentAllocatedSize。", hintEn: "Shows current process memory usage and the currentAllocatedSize of the MTLDevice."),
        MetalHUDElement(raw: "refreshrate", zh: "屏幕刷新率", en: "Screen Refresh Rate", ja: "リフレッシュレート",
                        unitOrSampleZh: "单位: Hz (如 120 Hz)", unitOrSampleEn: "Unit: Hz (e.g. 120 Hz)", unitOrSampleJa: "単位: Hz (例: 120 Hz)",
                        hintZh: "显示 App 所在屏幕的当前刷新率。", hintEn: "Shows the current refresh rate of the display your app is on."),
        MetalHUDElement(raw: "thermal", zh: "热状态", en: "Thermal State", ja: "サーマル状態",
                        unitOrSampleZh: "状态: Nominal / Fair", unitOrSampleEn: "State: Nominal / Fair", unitOrSampleJa: "状態: Nominal / Fair",
                        hintZh: "显示机器当前的 thermalState。", hintEn: "Shows the current thermalState of the machine."),
        MetalHUDElement(raw: "gamemode", zh: "游戏模式", en: "Game Mode", ja: "ゲームモード",
                        unitOrSampleZh: "状态: ON / OFF", unitOrSampleEn: "State: ON / OFF", unitOrSampleJa: "状態: ON / OFF",
                        hintZh: "显示游戏模式的开关状态。", hintEn: "Shows the state of Game Mode (on or off)."),
        MetalHUDElement(raw: "fps", zh: "FPS", en: "FPS", ja: "フレームレート (FPS)",
                        unitOrSampleZh: "单位: FPS (如 60.0 FPS)", unitOrSampleEn: "Unit: FPS (e.g. 60.0 FPS)", unitOrSampleJa: "単位: FPS (例: 60.0 FPS)",
                        hintZh: "显示过去 120 帧每秒帧数的滚动平均值。", hintEn: "Rolling average of frames per second for the past 120 frames."),
        MetalHUDElement(raw: "fpsgraph", zh: "FPS 图表", en: "FPS Graph", ja: "FPS グラフ",
                        unitOrSampleZh: "单位: 120 帧折线图 (FPS)", unitOrSampleEn: "Unit: 120-frame Chart (FPS)", unitOrSampleJa: "単位: 120フレーム折れ線グラフ (FPS)",
                        hintZh: "以图表显示过去 120 帧的 FPS。", hintEn: "A chart graphing the FPS for the past 120 frames."),
        MetalHUDElement(raw: "framenumber", zh: "帧号", en: "Frame Number", ja: "フレーム番号",
                        unitOrSampleZh: "单位: 累计呈现帧数 (如 #14280)", unitOrSampleEn: "Unit: Frame Index (e.g. #14280)", unitOrSampleJa: "単位: 累計描画フレーム数 (例: #14280)",
                        hintZh: "显示当前帧号（自启动或上次重置以来的呈现次数，含插值帧）。", hintEn: "Current frame number. Counts interpolated frames when frame interpolation is enabled."),
        MetalHUDElement(raw: "gputime", zh: "GPU 时间", en: "GPU Time", ja: "GPU 処理時間",
                        unitOrSampleZh: "单位: ms (毫秒，如 8.2 ms)", unitOrSampleEn: "Unit: ms (e.g. 8.2 ms)", unitOrSampleJa: "単位: ms (ミリ秒, 例: 8.2 ms)",
                        hintZh: "显示过去 120 帧 GPU 时间的滚动平均值（基于命令缓冲区 gpuStart/EndTime）。", hintEn: "Rolling average of GPU time for the past 120 frames, computed from command buffer gpuStartTime/gpuEndTime."),
        MetalHUDElement(raw: "presentdelay", zh: "呈现延迟", en: "Present Delay", ja: "表示遅延 (Present Delay)",
                        unitOrSampleZh: "单位: ms (延迟，如 2.1 ms)", unitOrSampleEn: "Unit: ms (e.g. 2.1 ms)", unitOrSampleJa: "単位: ms (遅延, 例: 2.1 ms)",
                        hintZh: "显示过去 120 帧呈现延迟的滚动平均值（调用 presentDrawable 到上屏的间隔）。", hintEn: "Rolling average of present delay for the past 120 frames (interval from presentDrawable to display)."),
        MetalHUDElement(raw: "frameinterval", zh: "帧间隔", en: "Frame Interval", ja: "フレーム間隔",
                        unitOrSampleZh: "单位: ms (帧间隔，如 16.6 ms)", unitOrSampleEn: "Unit: ms (e.g. 16.6 ms)", unitOrSampleJa: "単位: ms (間隔, 例: 16.6 ms)",
                        hintZh: "显示过去 120 帧两个连续 MTLDrawable 上屏时间差的滚动平均值。", hintEn: "Rolling average of the on-glass time difference between two consecutive MTLDrawables for the past 120 frames."),
        MetalHUDElement(raw: "frameintervalgraph", zh: "帧间隔图表", en: "Frame Interval Graph", ja: "フレーム間隔グラフ",
                        unitOrSampleZh: "单位: 120 帧波动图 (ms)", unitOrSampleEn: "Unit: 120-frame Graph (ms)", unitOrSampleJa: "単位: 120フレーム推移図 (ms)",
                        hintZh: "以图表显示过去 120 帧的帧间隔。", hintEn: "A chart graphing the frame interval for the past 120 frames."),
        MetalHUDElement(raw: "frameintervalhistogram", zh: "帧间隔直方图", en: "Frame Interval Histogram", ja: "フレーム間隔ヒストグラム",
                        unitOrSampleZh: "单位: 刷新率分桶直方图", unitOrSampleEn: "Unit: Bucketed Histogram", unitOrSampleJa: "単位: リフレッシュレート別ヒストグラム",
                        hintZh: "以柱状图显示分桶帧间隔，桶大小为屏幕刷新率。", hintEn: "A bucketed frame interval bar chart. Bucket size is the display refresh rate."),
        MetalHUDElement(raw: "metalcpu", zh: "命令缓冲区与编码器数量", en: "Command Buffer & Encoder Count", ja: "コマンドバッファ・エンコーダ数",
                        unitOrSampleZh: "单位: ms / 数量 (如 2.4 ms, 8 Buffers)", unitOrSampleEn: "Unit: ms / Count (e.g. 2.4 ms, 8 Buffers)", unitOrSampleJa: "単位: ms / 個数 (例: 2.4 ms, 8 Buffers)",
                        hintZh: "显示上一帧调度到的命令缓冲区与编码器数量及 CPU 编码时间。", hintEn: "Number of scheduled command buffers and encoders, and their CPU encoding time for the last frame."),
        MetalHUDElement(raw: "gputimeline", zh: "编码器时间与 GPU 时间线", en: "Encoder Time & GPU Timeline", ja: "エンコーダ時間・GPUタイムライン",
                        unitOrSampleZh: "单位: 编码器 GPU 时间线图", unitOrSampleEn: "Unit: Encoder GPU Timeline", unitOrSampleJa: "単位: エンコーダGPUタイムライン",
                        hintZh: "显示各类编码器的 GPU 时间与 GPU 时间线图表（需开启编码器 GPU 时间追踪）。", hintEn: "Encoder GPU times per type and a GPU timeline graph. Requires encoder GPU time tracking."),
        MetalHUDElement(raw: "shaders", zh: "着色器编译器", en: "Shader Compiler", ja: "シェーダーコンパイラ",
                        unitOrSampleZh: "单位: 管线数 (如 12 Pipes, 0 Compiling)", unitOrSampleEn: "Unit: Pipelines (e.g. 12 Pipes, 0 Compiling)", unitOrSampleJa: "単位: パイプライン数 (例: 12 Pipes, 0 Compiling)",
                        hintZh: "显示着色器编译活动：管线状态数、缓存着色器数、已编译着色器数与编译时间图表。", hintEn: "Shader compiler activity: pipeline state count, cached/compiled shader counts, and a compilation-time graph."),
        MetalHUDElement(raw: "disk", zh: "磁盘使用", en: "Disk Usage", ja: "ディスク I/O",
                        unitOrSampleZh: "单位: MB/s (如 R: 120 MB/s, W: 0 MB/s)", unitOrSampleEn: "Unit: MB/s (e.g. R: 120 MB/s, W: 0 MB/s)", unitOrSampleJa: "単位: MB/s (例: R: 120 MB/s, W: 0 MB/s)",
                        hintZh: "显示系统上报的磁盘读取、写入与逻辑写入字节数。", hintEn: "Disk bytes read, written, and logical writes as reported by system usage."),
        MetalHUDElement(raw: "toplabeledcommandbuffers", zh: "高占用命令缓冲区（含标记）", en: "Top Labeled Command Buffers", ja: "高負荷コマンドバッファ（ラベル付き）",
                        unitOrSampleZh: "单位: 耗时 (如 ShadowPass: 3.2ms)", unitOrSampleEn: "Unit: Time (e.g. ShadowPass: 3.2ms)", unitOrSampleJa: "単位: 処理時間 (例: ShadowPass: 3.2ms)",
                        hintZh: "显示 GPU 占用最高且带 label 的命令缓冲区（需开启编码器 GPU 时间追踪）。", hintEn: "Most GPU-intensive labeled command buffers. Requires encoder GPU time tracking."),
        MetalHUDElement(raw: "toplabeledencoders", zh: "高占用编码器（含标记）", en: "Top Labeled Encoders", ja: "高負荷エンコーダ（ラベル付き）",
                        unitOrSampleZh: "单位: 耗时 (如 DeferredLight: 2.8ms)", unitOrSampleEn: "Unit: Time (e.g. DeferredLight: 2.8ms)", unitOrSampleJa: "単位: 処理時間 (例: DeferredLight: 2.8ms)",
                        hintZh: "显示 GPU 占用最高且带 label 的编码器（需开启编码器 GPU 时间追踪）。", hintEn: "Most GPU-intensive labeled encoders. Requires encoder GPU time tracking."),
        MetalHUDElement(raw: "metalfx", zh: "MetalFX", en: "MetalFX", ja: "MetalFX アップスケーリング",
                        unitOrSampleZh: "示例: 缩放模式 (1080p -> 4K)", unitOrSampleEn: "e.g. Upscaling (1080p -> 4K)", unitOrSampleJa: "例: アップスケーリング (1080p -> 4K)",
                        hintZh: "显示 MetalFX 相关指标（属于瞬态指标，禁用 MetalFX 时自动隐藏）。", hintEn: "MetalFX metrics. Transient — automatically hidden when MetalFX is disabled.")
    ]
}

public struct MetalHUDOptions: Codable, Equatable, Sendable {
    public var opacity: Double = 1.0
    public var scale: Double = 0.2
    public var alignment: String = "topright"
    public var positionX: Int? = nil
    public var positionY: Int? = nil
    public var elements: [String] = []
    public var logEnabled: Bool = false
    public var shaderLogEnabled: Bool = false
    public var encoderTimingEnabled: Bool = false
    public var encoderGpuTimelineFrameCount: Int? = nil
    public var encoderGpuTimelineSwapDelta: Int? = nil
    public var showZeroMetrics: Bool = false
    public var showMetricsRange: Bool = false
    public var metricTimeout: Int? = nil
    public var insightsEnabled: Bool = false
    public var insightTimeout: Int? = nil
    public var insightReportInterval: Int? = nil
    public var rusageUpdateInterval: Int? = nil
    public var reportURL: String? = nil
    public var disableMenuBar: Bool = false
    public var configFilePath: String? = nil

    public init(
        opacity: Double = 1.0,
        scale: Double = 0.2,
        alignment: String = "topright",
        positionX: Int? = nil,
        positionY: Int? = nil,
        elements: [String] = [],
        logEnabled: Bool = false,
        shaderLogEnabled: Bool = false,
        encoderTimingEnabled: Bool = false,
        encoderGpuTimelineFrameCount: Int? = nil,
        encoderGpuTimelineSwapDelta: Int? = nil,
        showZeroMetrics: Bool = false,
        showMetricsRange: Bool = false,
        metricTimeout: Int? = nil,
        insightsEnabled: Bool = false,
        insightTimeout: Int? = nil,
        insightReportInterval: Int? = nil,
        rusageUpdateInterval: Int? = nil,
        reportURL: String? = nil,
        disableMenuBar: Bool = false,
        configFilePath: String? = nil
    ) {
        self.opacity = opacity
        self.scale = scale
        self.alignment = alignment
        self.positionX = positionX
        self.positionY = positionY
        self.elements = elements
        self.logEnabled = logEnabled
        self.shaderLogEnabled = shaderLogEnabled
        self.encoderTimingEnabled = encoderTimingEnabled
        self.encoderGpuTimelineFrameCount = encoderGpuTimelineFrameCount
        self.encoderGpuTimelineSwapDelta = encoderGpuTimelineSwapDelta
        self.showZeroMetrics = showZeroMetrics
        self.showMetricsRange = showMetricsRange
        self.metricTimeout = metricTimeout
        self.insightsEnabled = insightsEnabled
        self.insightTimeout = insightTimeout
        self.insightReportInterval = insightReportInterval
        self.rusageUpdateInterval = rusageUpdateInterval
        self.reportURL = reportURL
        self.disableMenuBar = disableMenuBar
        self.configFilePath = configFilePath
    }

    private enum CodingKeys: String, CodingKey {
        case opacity, scale, alignment, positionX, positionY, elements
        case logEnabled, shaderLogEnabled, encoderTimingEnabled
        case encoderGpuTimelineFrameCount, encoderGpuTimelineSwapDelta
        case showZeroMetrics, showMetricsRange, metricTimeout
        case insightsEnabled, insightTimeout, insightReportInterval, rusageUpdateInterval
        case reportURL, disableMenuBar, configFilePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 0.2
        alignment = try container.decodeIfPresent(String.self, forKey: .alignment) ?? "topright"
        positionX = try container.decodeIfPresent(Int.self, forKey: .positionX)
        positionY = try container.decodeIfPresent(Int.self, forKey: .positionY)
        elements = try container.decodeIfPresent([String].self, forKey: .elements) ?? []
        logEnabled = try container.decodeIfPresent(Bool.self, forKey: .logEnabled) ?? false
        shaderLogEnabled = try container.decodeIfPresent(Bool.self, forKey: .shaderLogEnabled) ?? false
        encoderTimingEnabled = try container.decodeIfPresent(Bool.self, forKey: .encoderTimingEnabled) ?? false
        encoderGpuTimelineFrameCount = try container.decodeIfPresent(Int.self, forKey: .encoderGpuTimelineFrameCount)
        encoderGpuTimelineSwapDelta = try container.decodeIfPresent(Int.self, forKey: .encoderGpuTimelineSwapDelta)
        showZeroMetrics = try container.decodeIfPresent(Bool.self, forKey: .showZeroMetrics) ?? false
        showMetricsRange = try container.decodeIfPresent(Bool.self, forKey: .showMetricsRange) ?? false
        metricTimeout = try container.decodeIfPresent(Int.self, forKey: .metricTimeout)
        insightsEnabled = try container.decodeIfPresent(Bool.self, forKey: .insightsEnabled) ?? false
        insightTimeout = try container.decodeIfPresent(Int.self, forKey: .insightTimeout)
        insightReportInterval = try container.decodeIfPresent(Int.self, forKey: .insightReportInterval)
        rusageUpdateInterval = try container.decodeIfPresent(Int.self, forKey: .rusageUpdateInterval)
        reportURL = try container.decodeIfPresent(String.self, forKey: .reportURL)
        disableMenuBar = try container.decodeIfPresent(Bool.self, forKey: .disableMenuBar) ?? false
        configFilePath = try container.decodeIfPresent(String.self, forKey: .configFilePath)
    }
}

public enum NavigationCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case overview
    case frameGen
    case metalHUD
    case gameBoost
    case storage
    case system
    case about

    public var id: String { rawValue }

    public var titleZh: String {
        switch self {
        case .overview: return "概览与状态"
        case .frameGen: return "画质与补帧"
        case .metalHUD: return "Metal HUD 调优"
        case .gameBoost: return "游戏加速与启动"
        case .storage: return "存储与磁盘"
        case .system: return "系统与偏好"
        case .about: return "关于与致谢"
        }
    }

    public var titleEn: String {
        switch self {
        case .overview: return "Overview"
        case .frameGen: return "Scaling & Frame Gen"
        case .metalHUD: return "Metal HUD Tuner"
        case .gameBoost: return "Game Boost"
        case .storage: return "Storage & Disks"
        case .system: return "System & Tools"
        case .about: return "About & Thanks"
        }
    }

    public var titleJa: String {
        switch self {
        case .overview: return "概要とステータス"
        case .frameGen: return "超解像と補フレーム"
        case .metalHUD: return "Metal HUD 設定"
        case .gameBoost: return "ゲーム高速化・起動"
        case .storage: return "ストレージとセーブ"
        case .system: return "システムと設定"
        case .about: return "情報と謝辞"
        }
    }

    public var iconName: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .frameGen: return "sparkles.tv"
        case .metalHUD: return "chart.xyaxis.line"
        case .gameBoost: return "bolt.fill"
        case .storage: return "externaldrive.fill"
        case .system: return "gearshape.2.fill"
        case .about: return "info.circle.fill"
        }
    }
}

public enum NavigationLayoutMode: String, Codable, CaseIterable, Sendable {
    case sidebar
    case commandCenter

    public var titleZh: String {
        switch self {
        case .sidebar: return "侧边栏模式"
        case .commandCenter: return "控制台模式"
        }
    }

    public var titleEn: String {
        switch self {
        case .sidebar: return "Sidebar View"
        case .commandCenter: return "Command Center"
        }
    }

    public var titleJa: String {
        switch self {
        case .sidebar: return "サイドバー表示"
        case .commandCenter: return "コマンドセンター"
        }
    }

    public var iconName: String {
        switch self {
        case .sidebar: return "sidebar.left"
        case .commandCenter: return "rectangle.grid.2x2.fill"
        }
    }
}

public enum WineBottleType: String, Codable, CaseIterable, Sendable {
    case crossover = "CrossOver"
    case whisky = "Whisky"
    case heroic = "Heroic"
    case customWine = "Wine Prefix"
    case other = "Other"

    public var iconName: String {
        switch self {
        case .crossover: return "shippingbox.fill"
        case .whisky: return "wineglass.fill"
        case .heroic: return "gamecontroller.fill"
        case .customWine: return "folder.fill.badge.gearshape"
        case .other: return "folder.fill"
        }
    }
}

public struct WineBottle: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public let name: String
    public let type: WineBottleType
    public let path: String
    public let windowsVersion: String?
    public let installedApps: [String]

    public init(name: String, type: WineBottleType, path: String, windowsVersion: String? = nil, installedApps: [String] = []) {
        self.name = name
        self.type = type
        self.path = path
        self.windowsVersion = windowsVersion
        self.installedApps = installedApps
    }
}

/// A connected iPhone/iPad as reported by Xcode's CoreDevice stack
/// (`xcrun devicectl list devices`).
///
/// Only devices whose hardware platform is iOS/iPadOS are ever built from the
/// inventory; other CoreDevice-managed hardware (Macs, Apple TVs, watches) is
/// filtered out before this type is constructed.
public struct IOSDevice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let model: String
    public let osVersion: String
    public let state: String

    public init(id: String, name: String, model: String = "", osVersion: String = "", state: String = "") {
        self.id = id
        self.name = name
        self.model = model
        self.osVersion = osVersion
        self.state = state
    }

    public var displayName: String { name.isEmpty ? id : name }

    /// Secondary line for lists: model, OS version and connection state,
    /// skipping whatever the device did not report.
    public var detailText: String {
        [model, osVersion, state].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// One app installed on a connected iOS device, as reported by
/// `xcrun devicectl device info apps`.
public struct IOSInstalledApp: Identifiable, Hashable, Sendable {
    public let bundleIdentifier: String
    public let displayName: String
    public let version: String

    public init(bundleIdentifier: String, displayName: String, version: String = "") {
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
    }

    public var id: String { bundleIdentifier }
}

public struct GameSaveLocation: Identifiable, Codable, Equatable, Sendable {
    public var id: String { path }
    public let bottleName: String
    public let gameName: String
    public let category: String
    public let path: String
    public let sizeFormatted: String
    public let lastModified: Date

    public init(bottleName: String, gameName: String, category: String, path: String, sizeFormatted: String, lastModified: Date) {
        self.bottleName = bottleName
        self.gameName = gameName
        self.category = category
        self.path = path
        self.sizeFormatted = sizeFormatted
        self.lastModified = lastModified
    }
}

public struct PerAppMetalHUDProfile: Identifiable, Codable, Equatable, Sendable {
    public var id: String { appPath }
    public var appPath: String
    public var appName: String
    public var options: MetalHUDOptions
    public var updatedAt: Date

    public init(appPath: String, appName: String, options: MetalHUDOptions, updatedAt: Date = Date()) {
        self.appPath = appPath
        self.appName = appName
        self.options = options
        self.updatedAt = updatedAt
    }
}

public enum HealthItemStatus: String, Codable, Sendable {
    case healthy
    case warning
    case error

    public var iconName: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
}

public struct HealthCheckItem: Identifiable, Codable, Equatable, Sendable {
    public var id: String { nameZh }
    public let nameZh: String
    public let nameEn: String
    public let nameJa: String
    public let status: HealthItemStatus
    public let detailZh: String
    public let detailEn: String
    public let detailJa: String

    public init(nameZh: String, nameEn: String, nameJa: String = "", status: HealthItemStatus, detailZh: String, detailEn: String, detailJa: String = "") {
        self.nameZh = nameZh
        self.nameEn = nameEn
        self.nameJa = nameJa.isEmpty ? nameEn : nameJa
        self.status = status
        self.detailZh = detailZh
        self.detailEn = detailEn
        self.detailJa = detailJa.isEmpty ? detailEn : detailJa
    }
}

public struct SystemHealthReport: Codable, Equatable, Sendable {
    public var items: [HealthCheckItem]
    public var legacyHelpersFound: [String]
    public var checkedAt: Date

    public var allHealthy: Bool {
        items.allSatisfy { $0.status == .healthy } && legacyHelpersFound.isEmpty
    }

    public init(items: [HealthCheckItem] = [], legacyHelpersFound: [String] = [], checkedAt: Date = Date()) {
        self.items = items
        self.legacyHelpersFound = legacyHelpersFound
        self.checkedAt = checkedAt
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 3
    public var didImportLegacyConfiguration = false
    public var defaultPaths: [String] = []
    public var diskPresets: [DiskPreset] = []
    public var automaticallyRestoreMountsOnLaunch = false
    public var restorableDiskMounts: [DiskPreset] = []
    public var hostnameBackup: HostnameBackup?
    public var recentMetalHUDApps: [RecentMetalHUDApp] = []
    public var hoYoWaitSeconds = 15
    public var excludesSensitiveCacheFiles = true
    public var metalHUDOptions = MetalHUDOptions()
    public var navigationLayoutMode: NavigationLayoutMode = .sidebar
    public var perAppHUDProfiles: [PerAppMetalHUDProfile] = []
    public var savedGameBackupsDirectory: String?
    public var languagePreference: AppLanguagePreference = .system
    public var scalingSettings: ScalingSettings = ScalingSettings()
    /// Process names (executable display names) the user pinned for one-tap
    /// priority optimisation. Empty by default so schema 3 stays readable.
    public var favoriteProcessNames: [String] = []
    /// When true the HoYo launch assistant still rewrites and restores hosts but
    /// leaves Wine process priority untouched.
    public var doesNotRaiseHoYoPriority = false
    /// When true the app keeps the legacy `macgametoolbox.helper` daemon for
    /// side-by-side installs and never deletes it during helper installation.
    public var legacyHelperCoexistence = false

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, didImportLegacyConfiguration, defaultPaths, diskPresets
        case automaticallyRestoreMountsOnLaunch, restorableDiskMounts, hostnameBackup
        case recentMetalHUDApps, hoYoWaitSeconds, excludesSensitiveCacheFiles, metalHUDOptions, navigationLayoutMode
        case perAppHUDProfiles, savedGameBackupsDirectory, languagePreference, scalingSettings
        case favoriteProcessNames, doesNotRaiseHoYoPriority, legacyHelperCoexistence
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        didImportLegacyConfiguration = try container.decodeIfPresent(Bool.self, forKey: .didImportLegacyConfiguration) ?? false
        defaultPaths = try container.decodeIfPresent([String].self, forKey: .defaultPaths) ?? []
        diskPresets = try container.decodeIfPresent([DiskPreset].self, forKey: .diskPresets) ?? []
        automaticallyRestoreMountsOnLaunch = try container.decodeIfPresent(Bool.self, forKey: .automaticallyRestoreMountsOnLaunch) ?? false
        restorableDiskMounts = try container.decodeIfPresent([DiskPreset].self, forKey: .restorableDiskMounts) ?? []
        hostnameBackup = try container.decodeIfPresent(HostnameBackup.self, forKey: .hostnameBackup)
        recentMetalHUDApps = try container.decodeIfPresent([RecentMetalHUDApp].self, forKey: .recentMetalHUDApps) ?? []
        let decodedWait = try container.decodeIfPresent(Int.self, forKey: .hoYoWaitSeconds) ?? 15
        hoYoWaitSeconds = [10, 15, 20].contains(decodedWait) ? decodedWait : 15
        excludesSensitiveCacheFiles = try container.decodeIfPresent(Bool.self, forKey: .excludesSensitiveCacheFiles) ?? true
        metalHUDOptions = try container.decodeIfPresent(MetalHUDOptions.self, forKey: .metalHUDOptions) ?? MetalHUDOptions()
        navigationLayoutMode = try container.decodeIfPresent(NavigationLayoutMode.self, forKey: .navigationLayoutMode) ?? .sidebar
        perAppHUDProfiles = try container.decodeIfPresent([PerAppMetalHUDProfile].self, forKey: .perAppHUDProfiles) ?? []
        savedGameBackupsDirectory = try container.decodeIfPresent(String.self, forKey: .savedGameBackupsDirectory)
        languagePreference = try container.decodeIfPresent(AppLanguagePreference.self, forKey: .languagePreference) ?? .system
        scalingSettings = try container.decodeIfPresent(ScalingSettings.self, forKey: .scalingSettings) ?? ScalingSettings()
        favoriteProcessNames = try container.decodeIfPresent([String].self, forKey: .favoriteProcessNames) ?? []
        doesNotRaiseHoYoPriority = try container.decodeIfPresent(Bool.self, forKey: .doesNotRaiseHoYoPriority) ?? false
        legacyHelperCoexistence = try container.decodeIfPresent(Bool.self, forKey: .legacyHelperCoexistence) ?? false
    }
}

public enum ToolboxError: LocalizedError, Equatable {
    case invalidPath(String)
    case invalidDisk(String)
    case commandFailed(String)
    case authorizationCancelled
    case helperApprovalRequired
    case helperUnavailable(String)
    case helperTimedOut
    case malformedOutput(String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path): coreText("无效路径：\(path)", "Invalid path: \(path)", "無効なパス：\(path)")
        case .invalidDisk(let disk): coreText("无效磁盘：\(disk)", "Invalid disk: \(disk)", "無効なディスク：\(disk)")
        case .commandFailed(let message): message
        case .authorizationCancelled: coreText("已取消管理员授权", "Authorization cancelled", "管理者認証がキャンセルされました")
        case .helperApprovalRequired: coreText("辅助服务需要在系统设置的“登录项与扩展”中批准", "Approve the helper in System Settings > Login Items & Extensions", "システム設定の「ログイン項目と拡張機能」でヘルパーを許可してください")
        case .helperUnavailable(let message): coreText("辅助服务不可用：\(message)", "Privileged helper unavailable: \(message)", "特権ヘルパーが利用できません：\(message)")
        case .helperTimedOut: coreText("辅助服务响应超时", "Privileged helper timed out", "特権ヘルパーの応答がタイムアウトしました")
        case .malformedOutput(let message): coreText("无法解析系统输出：\(message)", "Invalid system output: \(message)", "システム出力を解析できません：\(message)")
        }
    }
}
