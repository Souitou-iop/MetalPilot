import Foundation
@preconcurrency import Metal
@preconcurrency import CoreVideo
@preconcurrency import VideoToolbox
@preconcurrency import IOSurface

@available(macOS 26.0, *)
public final class MotionEstimator: @unchecked Sendable {
    private let device: MTLDevice
    private var session: __VTMotionEstimationSession?
    private var size: (width: Int, height: Int) = (0, 0)
    private var lumaBuffers: [CVPixelBuffer] = []
    private var lumaTextures: [MTLTexture] = []
    private var slot = 0
    private var hasReference = false

    public init(device: MTLDevice) {
        self.device = device
    }

    public func reset() {
        if let session {
            __VTMotionEstimationSessionInvalidate(session)
        }
        session = nil
        size = (0, 0)
        lumaBuffers.removeAll()
        lumaTextures.removeAll()
        slot = 0
        hasReference = false
    }

    private func ensureSession(width: Int, height: Int) -> Bool {
        if session != nil, size == (width, height) { return true }
        reset()

        let options: [String: Any] = [
            kVTMotionEstimationSessionCreationOption_UseMultiPassSearch as String: false as CFBoolean
        ]
        var created: __VTMotionEstimationSession?
        guard __VTMotionEstimationSessionCreate(kCFAllocatorDefault, options as CFDictionary,
                                                UInt32(width), UInt32(height), &created) == noErr,
              let created else { return false }

        var attributes: CFDictionary?
        __VTMotionEstimationSessionCopySourcePixelBufferAttributes(created, &attributes)
        var descriptor = (attributes as? [String: Any]) ?? [:]
        descriptor[kCVPixelBufferIOSurfacePropertiesKey as String] = [:] as CFDictionary

        for _ in 0..<2 {
            var buffer: CVPixelBuffer?
            guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                      kCVPixelFormatType_OneComponent8,
                                      descriptor as CFDictionary, &buffer) == kCVReturnSuccess,
                  let buffer,
                  let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return false }

            let texDescriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
            texDescriptor.usage = [.shaderRead, .shaderWrite]
            guard let texture = device.makeTexture(descriptor: texDescriptor, iosurface: surface, plane: 0) else {
                return false
            }
            lumaBuffers.append(buffer)
            lumaTextures.append(texture)
        }

        session = created
        size = (width, height)
        return true
    }

    public func prepare(width: Int, height: Int) -> MTLTexture? {
        guard ensureSession(width: width, height: height) else { return nil }
        return lumaTextures[slot]
    }

    public func estimate() -> CVPixelBuffer? {
        guard let session, lumaBuffers.count == 2 else { return nil }
        let current = lumaBuffers[slot]
        let reference = lumaBuffers[1 - slot]
        slot = 1 - slot

        guard hasReference else {
            hasReference = true
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: CVPixelBuffer?
        let status = __VTMotionEstimationSessionEstimateMotionVectors(
            session, reference, current, [], nil
        ) { status, _, _, vectors in
            if status == noErr { result = vectors }
            semaphore.signal()
        }
        guard status == noErr else { return nil }
        semaphore.wait()
        return result
    }

    public func texture(for vectors: CVPixelBuffer) -> MTLTexture? {
        guard let surface = CVPixelBufferGetIOSurface(vectors)?.takeUnretainedValue() else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg16Float,
            width: CVPixelBufferGetWidth(vectors),
            height: CVPixelBufferGetHeight(vectors),
            mipmapped: false)
        descriptor.usage = [.shaderRead]
        return device.makeTexture(descriptor: descriptor, iosurface: surface, plane: 0)
    }
}
