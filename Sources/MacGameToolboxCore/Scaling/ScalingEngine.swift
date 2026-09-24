import Foundation
import AppKit
@preconcurrency import Metal
@preconcurrency import MetalKit
@preconcurrency import MetalFX
@preconcurrency import IOSurface
import QuartzCore
import os
@preconcurrency import CoreVideo
@preconcurrency import VideoToolbox

public final class ScalingEngine: NSObject, MTKViewDelegate, @unchecked Sendable {
    private var _stats = ScalingPipelineStats()
    private let statsLock = OSAllocatedUnfairLock()
    private let renderStateLock = OSAllocatedUnfairLock()

    public var stats: ScalingPipelineStats {
        statsLock.lock()
        defer { statsLock.unlock() }
        return _stats
    }

    private let errorLock = OSAllocatedUnfairLock()
    private var reportedErrors: Set<String> = []
    private var pendingErrors: [String] = []

    nonisolated(unsafe) public static var lastInitError: String?

    public func reportError(_ message: String) {
        errorLock.lock()
        defer { errorLock.unlock() }
        guard reportedErrors.insert(message).inserted else { return }
        pendingErrors.append(message)
    }

    public func consumePendingError() -> String? {
        errorLock.lock()
        defer { errorLock.unlock() }
        return pendingErrors.isEmpty ? nil : pendingErrors.removeFirst()
    }

    private let processingQueue = DispatchQueue(label: "com.metalpilot.scaling.engine", qos: .userInteractive)
    private static let maxInFlight = 3
    private let inFlightSemaphore = DispatchSemaphore(value: ScalingEngine.maxInFlight)

    public var deviceName: String { device.name }
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    private var spatialScaler: MTLFXSpatialScaler?
    private var captureScaler: MTLFXSpatialScaler?
    private var captureUpscaledTexture: MTLTexture?

    private var casPipeline: MTLComputePipelineState?
    private var fxaaPipeline: MTLComputePipelineState?
    private var smaaEdgePipeline: MTLComputePipelineState?
    private var smaaWeightPipeline: MTLComputePipelineState?
    private var smaaBlendPipeline: MTLComputePipelineState?
    private var taaPipeline: MTLComputePipelineState?
    private var copyPipeline: MTLComputePipelineState?
    private var lumaPipeline: MTLComputePipelineState?
    private var extrapolatePipeline: MTLComputePipelineState?

    private var flatDepthTexture: MTLTexture?
    private var _motionEstimatorStorage: Any?
    private var extrapolatedTexture: MTLTexture?

    private var renderPipeline: MTLRenderPipelineState?
    private var cursorPipeline: MTLRenderPipelineState?
    private var cursorTexture: MTLTexture?
    private var cursorTextureSize: CGSize = .zero
    private weak var mtkView: MTKView?

    private var upscaledTexture: MTLTexture?
    private var upscaleCacheKey: CFTimeInterval = -1

    private var casTexture: MTLTexture?
    private var smaaEdgeTexture: MTLTexture?
    private var smaaWeightTexture: MTLTexture?
    private var taaHistoryTexture: MTLTexture?
    private var taaOutputTexture: MTLTexture?

    public struct FrameHistory: Sendable {
        public let texture: MTLTexture
        public let timestamp: CFTimeInterval
        public let isSceneCut: Bool
        public let motion: MTLTexture?
    }

    private final class FrameRingBuffer: @unchecked Sendable {
        private var buffer: [FrameHistory] = []
        static let capacity = ScalingEngine.maxInFlight + 1
        private let lock = NSLock()

        func push(_ frame: FrameHistory) {
            lock.lock()
            defer { lock.unlock() }
            buffer.append(frame)
            if buffer.count > Self.capacity {
                buffer.removeFirst()
            }
        }

        func getFramesForTime(_ targetTime: CFTimeInterval) -> (prev: FrameHistory, next: FrameHistory)? {
            lock.lock()
            defer { lock.unlock() }
            guard buffer.count >= 2 else { return nil }
            for i in (0..<(buffer.count - 1)).reversed() {
                let prev = buffer[i]
                let next = buffer[i + 1]
                if prev.timestamp <= targetTime && targetTime <= next.timestamp {
                    return (prev, next)
                }
            }
            return (buffer[buffer.count - 2], buffer[buffer.count - 1])
        }

        func latest() -> FrameHistory? {
            lock.lock()
            defer { lock.unlock() }
            return buffer.last
        }

        func clear() {
            lock.lock()
            defer { lock.unlock() }
            buffer.removeAll()
        }
    }

    private let ringBuffer = FrameRingBuffer()

    public var settings: ScalingSettings = ScalingSettings()

    // Cursor position tracking
    private var cursorPosition: SIMD2<Float> = .zero
    private var cursorVisible: Bool = false
    private let cursorLock = OSAllocatedUnfairLock()

    public init?(metalDevice: MTLDevice? = nil) {
        guard let dev = metalDevice ?? MTLCreateSystemDefaultDevice(),
              let queue = dev.makeCommandQueue() else {
            Self.lastInitError = "Failed to create Metal device or command queue."
            return nil
        }
        self.device = dev
        self.commandQueue = queue
        super.init()

        guard initPipelines() else {
            return nil
        }
    }

    private func initPipelines() -> Bool {
        var library: MTLLibrary?
        if let compiledLib = try? device.makeLibrary(source: ScalingShadersSource.source, options: nil) {
            library = compiledLib
        } else {
            library = device.makeDefaultLibrary()
        }

        guard let lib = library else {
            Self.lastInitError = "Failed to load Metal library."
            return false
        }

        do {
            if let casFunc = lib.makeFunction(name: "contrastAdaptiveSharpening") {
                casPipeline = try device.makeComputePipelineState(function: casFunc)
            }
            if let fxaaFunc = lib.makeFunction(name: "fxaa") {
                fxaaPipeline = try device.makeComputePipelineState(function: fxaaFunc)
            }
            if let smaaEdgeFunc = lib.makeFunction(name: "smaaEdgeDetection") {
                smaaEdgePipeline = try device.makeComputePipelineState(function: smaaEdgeFunc)
            }
            if let smaaWeightFunc = lib.makeFunction(name: "smaaBlendingWeights") {
                smaaWeightPipeline = try device.makeComputePipelineState(function: smaaWeightFunc)
            }
            if let smaaBlendFunc = lib.makeFunction(name: "smaaBlend") {
                smaaBlendPipeline = try device.makeComputePipelineState(function: smaaBlendFunc)
            }
            if let taaFunc = lib.makeFunction(name: "taa") {
                taaPipeline = try device.makeComputePipelineState(function: taaFunc)
            }
            if let copyFunc = lib.makeFunction(name: "copyTexture") {
                copyPipeline = try device.makeComputePipelineState(function: copyFunc)
            }
            if let lumaFunc = lib.makeFunction(name: "bgraToLuma") {
                lumaPipeline = try device.makeComputePipelineState(function: lumaFunc)
            }
            if let extraFunc = lib.makeFunction(name: "extrapolateFrame") {
                extrapolatePipeline = try device.makeComputePipelineState(function: extraFunc)
            }

            let renderDesc = MTLRenderPipelineDescriptor()
            renderDesc.vertexFunction = lib.makeFunction(name: "texture_vertex")
            renderDesc.fragmentFunction = lib.makeFunction(name: "texture_fragment")
            renderDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            renderPipeline = try device.makeRenderPipelineState(descriptor: renderDesc)

            let cursorDesc = MTLRenderPipelineDescriptor()
            cursorDesc.vertexFunction = lib.makeFunction(name: "cursor_vertex")
            cursorDesc.fragmentFunction = lib.makeFunction(name: "cursor_fragment")
            cursorDesc.colorAttachments[0].pixelFormat = .bgra8Unorm
            cursorDesc.colorAttachments[0].isBlendingEnabled = true
            cursorDesc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            cursorDesc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            cursorDesc.colorAttachments[0].sourceAlphaBlendFactor = .one
            cursorDesc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            cursorPipeline = try device.makeRenderPipelineState(descriptor: cursorDesc)

            return true
        } catch {
            Self.lastInitError = "Pipeline initialization failed: \(error.localizedDescription)"
            return false
        }
    }

    @MainActor
    public func setMTKView(_ view: MTKView) {
        self.mtkView = view
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.preferredFramesPerSecond = 120
    }

    public func updateCursor(position: CGPoint, windowBounds: CGRect, isVisible: Bool) {
        cursorLock.lock()
        defer { cursorLock.unlock() }
        cursorVisible = isVisible
        guard windowBounds.width > 0, windowBounds.height > 0 else { return }
        let normX = Float((position.x / windowBounds.width) * 2.0 - 1.0)
        let normY = Float(1.0 - (position.y / windowBounds.height) * 2.0)
        cursorPosition = SIMD2<Float>(normX, normY)
    }

    // MARK: - Frame Delivery from Capture Service

    public func processCapturedFrame(
        surface: IOSurfaceRef,
        pixelBuffer: CVPixelBuffer,
        timestamp: Double,
        isSceneCut: Bool
    ) {
        processingQueue.async { [weak self] in
            guard let self else { return }

            let width = IOSurfaceGetWidth(surface)
            let height = IOSurfaceGetHeight(surface)
            guard width > 0, height > 0 else { return }

            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
            descriptor.usage = [.shaderRead, .shaderWrite, .renderTarget]

            guard let rawTexture = self.device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0) else {
                return
            }

            var motionTexture: MTLTexture? = nil

            if #available(macOS 26.0, *) {
                if self.settings.frameGenMode.isExtrapolation {
                    if self._motionEstimatorStorage == nil {
                        self._motionEstimatorStorage = MotionEstimator(device: self.device)
                    }
                    if let motionEstimator = self._motionEstimatorStorage as? MotionEstimator {
                        if let lumaDest = motionEstimator.prepare(width: width, height: height),
                           let lumaPipe = self.lumaPipeline,
                           let cmdBuffer = self.commandQueue.makeCommandBuffer(),
                           let encoder = cmdBuffer.makeComputeCommandEncoder() {
                            encoder.setComputePipelineState(lumaPipe)
                            encoder.setTexture(rawTexture, index: 0)
                            encoder.setTexture(lumaDest, index: 1)
                            let w = (width + 15) / 16
                            let h = (height + 15) / 16
                            encoder.dispatchThreadgroups(MTLSize(width: w, height: h, depth: 1),
                                                         threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                            encoder.endEncoding()
                            cmdBuffer.commit()
                            cmdBuffer.waitUntilCompleted()

                            if let vectors = motionEstimator.estimate() {
                                motionTexture = motionEstimator.texture(for: vectors)
                            }
                        }
                    }
                }
            }

            let history = FrameHistory(
                texture: rawTexture,
                timestamp: timestamp,
                isSceneCut: isSceneCut,
                motion: motionTexture
            )
            self.ringBuffer.push(history)

            self.statsLock.lock()
            self._stats.frameCount += 1
            self._stats.captureFPS = 60.0
            self.statsLock.unlock()
        }
    }

    // MARK: - MTKViewDelegate (Rendering Loop)

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        upscaledTexture = nil
        casTexture = nil
        smaaEdgeTexture = nil
        smaaWeightTexture = nil
    }

    public func draw(in view: MTKView) {
        guard let currentDrawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor else {
            return
        }

        let outWidth = Int(view.drawableSize.width)
        let outHeight = Int(view.drawableSize.height)
        guard outWidth > 0, outHeight > 0 else { return }

        guard let latestFrame = ringBuffer.latest() else {
            // Nothing captured yet, clear screen
            guard let cmdBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }
            encoder.endEncoding()
            cmdBuffer.present(currentDrawable)
            cmdBuffer.commit()
            return
        }

        guard let cmdBuffer = commandQueue.makeCommandBuffer() else { return }

        var currentTexture = latestFrame.texture

        // Frame Generation Phase (Extrapolation)
        if settings.frameGenMode.isExtrapolation,
           let motion = latestFrame.motion,
           let extraPipe = extrapolatePipeline,
           !latestFrame.isSceneCut {
            if extrapolatedTexture == nil || extrapolatedTexture?.width != currentTexture.width || extrapolatedTexture?.height != currentTexture.height {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: currentTexture.width, height: currentTexture.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite]
                extrapolatedTexture = device.makeTexture(descriptor: desc)
            }

            if let extraDest = extrapolatedTexture,
               let encoder = cmdBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(extraPipe)
                encoder.setTexture(currentTexture, index: 0)
                encoder.setTexture(motion, index: 1)
                encoder.setTexture(extraDest, index: 2)

                var phase: Float = 0.5
                var blockSize: Float = 16.0
                encoder.setBytes(&phase, length: MemoryLayout<Float>.size, index: 0)
                encoder.setBytes(&blockSize, length: MemoryLayout<Float>.size, index: 1)

                let w = (currentTexture.width + 15) / 16
                let h = (currentTexture.height + 15) / 16
                encoder.dispatchThreadgroups(MTLSize(width: w, height: h, depth: 1),
                                             threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                encoder.endEncoding()
                currentTexture = extraDest
            }
        }

        // Post Processing: Anti-Aliasing (FXAA, SMAA, or TAA)
        if settings.aaMode == .fxaa, let fxaaPipe = fxaaPipeline {
            if smaaEdgeTexture == nil || smaaEdgeTexture?.width != currentTexture.width || smaaEdgeTexture?.height != currentTexture.height {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: currentTexture.width, height: currentTexture.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite]
                smaaEdgeTexture = device.makeTexture(descriptor: desc)
            }
            if let dest = smaaEdgeTexture, let encoder = cmdBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(fxaaPipe)
                encoder.setTexture(currentTexture, index: 0)
                encoder.setTexture(dest, index: 1)
                var threshold: Float = 0.125
                encoder.setBytes(&threshold, length: MemoryLayout<Float>.size, index: 0)
                let w = (currentTexture.width + 15) / 16
                let h = (currentTexture.height + 15) / 16
                encoder.dispatchThreadgroups(MTLSize(width: w, height: h, depth: 1),
                                             threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                encoder.endEncoding()
                currentTexture = dest
            }
        } else if settings.aaMode == .taa, let taaPipe = taaPipeline {
            if taaOutputTexture == nil || taaOutputTexture?.width != currentTexture.width || taaOutputTexture?.height != currentTexture.height {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: currentTexture.width, height: currentTexture.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite]
                taaOutputTexture = device.makeTexture(descriptor: desc)
            }
            if taaHistoryTexture == nil || taaHistoryTexture?.width != currentTexture.width || taaHistoryTexture?.height != currentTexture.height {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: currentTexture.width, height: currentTexture.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite]
                taaHistoryTexture = device.makeTexture(descriptor: desc)
            }
            let motion = latestFrame.motion ?? currentTexture
            if let dest = taaOutputTexture, let hist = taaHistoryTexture, let encoder = cmdBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(taaPipe)
                encoder.setTexture(currentTexture, index: 0)
                encoder.setTexture(hist, index: 1)
                encoder.setTexture(motion, index: 2)
                encoder.setTexture(dest, index: 3)
                var feedback: Float = 0.88
                encoder.setBytes(&feedback, length: MemoryLayout<Float>.size, index: 0)
                let w = (currentTexture.width + 15) / 16
                let h = (currentTexture.height + 15) / 16
                encoder.dispatchThreadgroups(MTLSize(width: w, height: h, depth: 1),
                                             threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                encoder.endEncoding()
                currentTexture = dest
                // Keep history updated
                taaHistoryTexture = dest
            }
        }

        // Post Processing: CAS (Contrast-Adaptive Sharpening)
        if settings.casEnabled, let casPipe = casPipeline {
            if casTexture == nil || casTexture?.width != currentTexture.width || casTexture?.height != currentTexture.height {
                let desc = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: currentTexture.width, height: currentTexture.height, mipmapped: false)
                desc.usage = [.shaderRead, .shaderWrite]
                casTexture = device.makeTexture(descriptor: desc)
            }
            if let dest = casTexture, let encoder = cmdBuffer.makeComputeCommandEncoder() {
                encoder.setComputePipelineState(casPipe)
                encoder.setTexture(currentTexture, index: 0)
                encoder.setTexture(dest, index: 1)
                var params = SharpenParams(sharpness: settings.sharpness)
                encoder.setBytes(&params, length: MemoryLayout<SharpenParams>.size, index: 0)
                let w = (currentTexture.width + 15) / 16
                let h = (currentTexture.height + 15) / 16
                encoder.dispatchThreadgroups(MTLSize(width: w, height: h, depth: 1),
                                             threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
                encoder.endEncoding()
                currentTexture = dest
            }
        }

        // Render pass to destination drawable
        if let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc),
           let renderPipe = renderPipeline {
            encoder.setRenderPipelineState(renderPipe)
            encoder.setFragmentTexture(currentTexture, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)

            // Render Synthetic Hardware Cursor if enabled
            cursorLock.lock()
            let showCur = cursorVisible && settings.syntheticCursorEnabled
            let curPos = cursorPosition
            cursorLock.unlock()

            if showCur, let curPipe = cursorPipeline {
                encoder.setRenderPipelineState(curPipe)
                var uniform = ScalingCursorUniforms(center: curPos, size: SIMD2<Float>(0.03, 0.03))
                encoder.setVertexBytes(&uniform, length: MemoryLayout<ScalingCursorUniforms>.size, index: 0)
                encoder.setFragmentTexture(currentTexture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            }

            encoder.endEncoding()
        }

        cmdBuffer.present(currentDrawable)
        cmdBuffer.commit()

        statsLock.lock()
        _stats.outputFrameCount += 1
        _stats.outputFPS = 120.0
        _stats.generatedFPS = settings.frameGenMode.isExtrapolation ? 60.0 : 0.0
        _stats.outputResolution = CGSize(width: outWidth, height: outHeight)
        statsLock.unlock()
    }

    public func reset() {
        ringBuffer.clear()
        if #available(macOS 26.0, *) {
            if let motionEstimator = _motionEstimatorStorage as? MotionEstimator {
                motionEstimator.reset()
            }
        }
    }
}
