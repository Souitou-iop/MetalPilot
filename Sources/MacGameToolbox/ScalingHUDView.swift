import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

public struct ScalingHUDView: View {
    let stats: ScalingPipelineStats
    let settings: ScalingSettings

    public init(stats: ScalingPipelineStats, settings: ScalingSettings) {
        self.stats = stats
        self.settings = settings
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles.tv")
                    .foregroundStyle(Color.accentColor)
                Text("MetalPilot • Frame Gen")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                Spacer()
            }
            Divider().opacity(0.3)

            HStack(spacing: 12) {
                metricColumn(title: "Capture", value: "\(Int(stats.captureFPS)) FPS", color: .green)
                if settings.frameGenMode != .off {
                    metricColumn(title: "Generated", value: "\(Int(stats.generatedFPS)) FPS", color: .cyan)
                }
                metricColumn(title: "Output", value: "\(Int(stats.outputFPS)) FPS", color: .orange)
            }

            Divider().opacity(0.2)

            HStack(spacing: 12) {
                metricLabel(key: "Mode", value: settings.frameGenMode.rawValue)
                metricLabel(key: "Scale", value: "\(Int(settings.renderScale.rawValue * 100))%")
                metricLabel(key: "AA", value: settings.aaMode.rawValue.uppercased())
                if settings.casEnabled {
                    metricLabel(key: "CAS", value: "\(Int(settings.sharpness * 100))%")
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        )
        .foregroundColor(.white)
        .frame(width: 280)
    }

    private func metricColumn(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
    }

    private func metricLabel(key: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(key + ":")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
        }
    }
}
