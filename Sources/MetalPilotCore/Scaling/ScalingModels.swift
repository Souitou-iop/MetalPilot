import Foundation
import CoreGraphics

public struct ScalingCursorUniforms {
    public var center: SIMD2<Float>
    public var size: SIMD2<Float>
    
    public init(center: SIMD2<Float> = .zero, size: SIMD2<Float> = .zero) {
        self.center = center
        self.size = size
    }
}

public struct SharpenParams {
    public var sharpness: Float
    public init(sharpness: Float = 0.5) {
        self.sharpness = sharpness
    }
}

public struct AntiAliasParams {
    public var threshold: Float
    public var maxSearchSteps: Int32
    public init(threshold: Float = 0.1, maxSearchSteps: Int32 = 16) {
        self.threshold = threshold
        self.maxSearchSteps = maxSearchSteps
    }
}

public enum FrameGenMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case off = "off"
    case extrapolation2x = "extrapolation2x"
    case extrapolation3x = "extrapolation3x"
    case extrapolation4x = "extrapolation4x"
    case interpolation2x = "interpolation2x"

    public var id: String { rawValue }

    public var isExtrapolation: Bool {
        self == .extrapolation2x || self == .extrapolation3x || self == .extrapolation4x
    }

    public var isInterpolation: Bool {
        self == .interpolation2x
    }

    public var multiplier: Int {
        switch self {
        case .off: return 1
        case .extrapolation2x, .interpolation2x: return 2
        case .extrapolation3x: return 3
        case .extrapolation4x: return 4
        }
    }

    public var titleZh: String {
        switch self {
        case .off: return "关闭补帧"
        case .extrapolation2x: return "零延迟硬件运动外推 (2x)"
        case .extrapolation3x: return "零延迟硬件运动外推 (3x)"
        case .extrapolation4x: return "零延迟硬件运动外推 (4x)"
        case .interpolation2x: return "MetalFX 光流插值 (2x)"
        }
    }

    public var titleEn: String {
        switch self {
        case .off: return "Off"
        case .extrapolation2x: return "Zero-Latency Extrapolation (2x)"
        case .extrapolation3x: return "Zero-Latency Extrapolation (3x)"
        case .extrapolation4x: return "Zero-Latency Extrapolation (4x)"
        case .interpolation2x: return "MetalFX Interpolation (2x)"
        }
    }

    public var titleJa: String {
        switch self {
        case .off: return "補フレーム無効"
        case .extrapolation2x: return "ゼロ遅延ハードウェア外挿 (2x)"
        case .extrapolation3x: return "ゼロ遅延ハードウェア外挿 (3x)"
        case .extrapolation4x: return "ゼロ遅延ハードウェア外挿 (4x)"
        case .interpolation2x: return "MetalFX オプティカルフロー補間 (2x)"
        }
    }
}

public enum ScalingRenderScale: Float, CaseIterable, Identifiable, Codable, Sendable {
    case scale100 = 1.0
    case scale75 = 0.75
    case scale67 = 0.6667
    case scale50 = 0.5
    case scale33 = 0.3333

    public var id: Float { rawValue }

    public var titleZh: String {
        switch self {
        case .scale100: return "原生 (100%)"
        case .scale75: return "超画质 (75%)"
        case .scale67: return "画质优先 (67%)"
        case .scale50: return "性能优先 (50%)"
        case .scale33: return "极速性能 (33%)"
        }
    }

    public var titleEn: String {
        switch self {
        case .scale100: return "Native (100%)"
        case .scale75: return "Ultra Quality (75%)"
        case .scale67: return "Quality (67%)"
        case .scale50: return "Performance (50%)"
        case .scale33: return "Ultra Performance (33%)"
        }
    }

    public var titleJa: String {
        switch self {
        case .scale100: return "ネイティブ (100%)"
        case .scale75: return "最高画質 (75%)"
        case .scale67: return "画質重視 (67%)"
        case .scale50: return "パフォーマンス (50%)"
        case .scale33: return "超高速 (33%)"
        }
    }
}

public enum ScalingAAMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case none = "none"
    case fxaa = "fxaa"
    case smaa = "smaa"
    case taa = "taa"

    public var id: String { rawValue }

    public var titleZh: String {
        switch self {
        case .none: return "无抗锯齿"
        case .fxaa: return "FXAA (快速近邻)"
        case .smaa: return "SMAA (形态学高级)"
        case .taa: return "TAA (时域抗锯齿)"
        }
    }

    public var titleEn: String {
        switch self {
        case .none: return "Off"
        case .fxaa: return "FXAA (Fast)"
        case .smaa: return "SMAA (Morphological)"
        case .taa: return "TAA (Temporal)"
        }
    }

    public var titleJa: String {
        switch self {
        case .none: return "アンチエイリアス無効"
        case .fxaa: return "FXAA (高速)"
        case .smaa: return "SMAA (高品位形態学)"
        case .taa: return "TAA (テンポラル)"
        }
    }
}

public enum ScalingQualityProfile: String, CaseIterable, Identifiable, Codable, Sendable {
    case performance = "performance"
    case balanced = "balanced"
    case ultra = "ultra"

    public var id: String { rawValue }

    public var titleZh: String {
        switch self {
        case .performance: return "性能优先"
        case .balanced: return "均衡模式"
        case .ultra: return "极致画质"
        }
    }

    public var titleEn: String {
        switch self {
        case .performance: return "Performance"
        case .balanced: return "Balanced"
        case .ultra: return "Ultra Quality"
        }
    }

    public var titleJa: String {
        switch self {
        case .performance: return "パフォーマンス"
        case .balanced: return "バランス"
        case .ultra: return "ウルトラ画質"
        }
    }
}

public struct ScalingPipelineStats: Equatable, Sendable {
    public var captureFPS: Float = 0
    public var outputFPS: Float = 0
    public var generatedFPS: Float = 0
    public var frameTime: Float = 0
    public var gpuTime: Float = 0
    public var captureGPUTime: Float = 0
    public var captureLatency: Float = 0
    public var presentLatency: Float = 0
    public var endToEndLatency: Float = 0
    public var avgFrameTime: Float = 0
    public var framePacingScore: Float = 100
    public var frameCount: UInt64 = 0
    public var outputFrameCount: UInt64 = 0
    public var droppedFrames: UInt64 = 0
    public var interpolatedFrameCount: UInt64 = 0
    public var passthroughFrameCount: UInt64 = 0
    public var generatedFrameCount: UInt64 = 0
    public var gpuMemoryUsed: UInt64 = 0
    public var gpuMemoryTotal: UInt64 = 0
    public var processMemoryUsed: UInt64 = 0
    public var cpuUsage: Float = 0
    public var outputResolution: CGSize = .zero
    public var screenRefreshRate: Int = 0
    public var isProMotion: Bool = false
    public var targetOutputFPS: Int = 0

    public init() {}
}

public struct ScalingSettings: Codable, Equatable, Sendable {
    public var enabled: Bool = false
    public var frameGenMode: FrameGenMode = .extrapolation2x
    public var renderScale: ScalingRenderScale = .scale75
    public var qualityProfile: ScalingQualityProfile = .balanced
    public var aaMode: ScalingAAMode = .smaa
    public var casEnabled: Bool = true
    public var sharpness: Float = 0.5
    public var sceneCutDetectionEnabled: Bool = true
    public var dynamicResolutionScaling: Bool = false
    public var syntheticCursorEnabled: Bool = true
    public var hudEnabled: Bool = true
    public var targetWindowBundleID: String? = nil
    public var targetWindowName: String? = nil
    public var vsync: Bool = true
    public var tripleBuffering: Bool = true

    public init(
        enabled: Bool = false,
        frameGenMode: FrameGenMode = .extrapolation2x,
        renderScale: ScalingRenderScale = .scale75,
        qualityProfile: ScalingQualityProfile = .balanced,
        aaMode: ScalingAAMode = .smaa,
        casEnabled: Bool = true,
        sharpness: Float = 0.5,
        sceneCutDetectionEnabled: Bool = true,
        dynamicResolutionScaling: Bool = false,
        syntheticCursorEnabled: Bool = true,
        hudEnabled: Bool = true,
        targetWindowBundleID: String? = nil,
        targetWindowName: String? = nil,
        vsync: Bool = true,
        tripleBuffering: Bool = true
    ) {
        self.enabled = enabled
        self.frameGenMode = frameGenMode
        self.renderScale = renderScale
        self.qualityProfile = qualityProfile
        self.aaMode = aaMode
        self.casEnabled = casEnabled
        self.sharpness = sharpness
        self.sceneCutDetectionEnabled = sceneCutDetectionEnabled
        self.dynamicResolutionScaling = dynamicResolutionScaling
        self.syntheticCursorEnabled = syntheticCursorEnabled
        self.hudEnabled = hudEnabled
        self.targetWindowBundleID = targetWindowBundleID
        self.targetWindowName = targetWindowName
        self.vsync = vsync
        self.tripleBuffering = tripleBuffering
    }
}
