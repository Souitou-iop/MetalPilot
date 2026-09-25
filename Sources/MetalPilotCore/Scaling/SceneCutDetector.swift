import Foundation
import CoreGraphics
import CoreVideo
@preconcurrency import IOSurface

public final class SceneCutDetector: @unchecked Sendable {
    private var lastLumaGrid: [UInt8]?
    private var changedFractionEMA: Double?
    private var changedFractionVarEMA: Double = 0
    private var cutWarmupRemaining: Int = 0

    private static let gridCols = 64
    private static let gridRows = 64
    private static let gridSize = gridCols * gridRows
    private static let lumaDeltaThreshold: Int = 30
    private static let warmupFrames = 5

    public init() {}

    public func reset() {
        lastLumaGrid = nil
        changedFractionEMA = nil
        changedFractionVarEMA = 0
        cutWarmupRemaining = 0
    }

    public func isSceneCut(pixelBuffer: CVPixelBuffer) -> Bool {
        guard let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue() else {
            return false
        }
        return evaluate(surface: surface)
    }

    public func evaluate(surface: IOSurfaceRef) -> Bool {
        guard IOSurfaceLock(surface, .readOnly, nil) == kIOReturnSuccess else { return false }
        defer { IOSurfaceUnlock(surface, .readOnly, nil) }

        let base = IOSurfaceGetBaseAddress(surface)
        let width = IOSurfaceGetWidth(surface)
        let height = IOSurfaceGetHeight(surface)
        let bpr = IOSurfaceGetBytesPerRow(surface)

        guard width >= Self.gridCols, height >= Self.gridRows else { return false }

        var grid = [UInt8](repeating: 0, count: Self.gridSize)
        let ptr = base.assumingMemoryBound(to: UInt8.self)

        for gy in 0..<Self.gridRows {
            let py = gy * height / Self.gridRows
            let rowStart = py * bpr
            for gx in 0..<Self.gridCols {
                let px = gx * width / Self.gridCols
                let offset = rowStart + px * 4
                // BGRA: B=0, G=1, R=2
                let b = Int(ptr[offset])
                let g = Int(ptr[offset + 1])
                let r = Int(ptr[offset + 2])
                let luma = (r * 299 + g * 587 + b * 114) / 1000
                grid[gy * Self.gridCols + gx] = UInt8(clamping: luma)
            }
        }

        guard let prev = lastLumaGrid else {
            lastLumaGrid = grid
            cutWarmupRemaining = Self.warmupFrames
            return false
        }
        lastLumaGrid = grid

        if cutWarmupRemaining > 0 {
            cutWarmupRemaining -= 1
            return false
        }

        var changedCells = 0
        for i in 0..<Self.gridSize {
            if abs(Int(grid[i]) - Int(prev[i])) > Self.lumaDeltaThreshold {
                changedCells += 1
            }
        }

        let changedFraction = Double(changedCells) / Double(Self.gridSize)
        let alpha = 0.05
        guard let mean = changedFractionEMA else {
            changedFractionEMA = changedFraction
            changedFractionVarEMA = 0.005
            return false
        }

        let stdDev = sqrt(max(changedFractionVarEMA, 1e-6))
        let dynamicCutThreshold = min(0.85, max(0.40, mean + 6.0 * stdDev))
        let cutDetected = changedFraction > dynamicCutThreshold

        if cutDetected {
            cutWarmupRemaining = 2
            changedFractionEMA = min(0.5, mean + 0.1)
        } else {
            let delta = changedFraction - mean
            changedFractionEMA = mean + alpha * delta
            changedFractionVarEMA = max(1e-6, (1.0 - alpha) * (changedFractionVarEMA + alpha * delta * delta))
        }

        return cutDetected
    }
}
