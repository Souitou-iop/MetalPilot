import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

// MARK: - App Version Helper

public enum AppVersion {
    public static var current: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "4.2.0"
    }

    public static var displayString: String {
        "v\(current)"
    }
}

// MARK: - Native Theme Tokens & Semantic Helpers

public enum GamingTheme {
    // Semantic Accent Colors (adapt naturally to dark/light)
    public static let neonEmerald = Color.green
    public static let cyberCyan = Color.cyan
    public static let electricViolet = Color.purple
    public static let amberWarning = Color.orange
    public static let coralRed = Color.red

    public static let bgDeepDark = Color(nsColor: .windowBackgroundColor)
    public static let bgSurfaceDark = Color(nsColor: .controlBackgroundColor)
}

// MARK: - Live Status Badge (Native Pill)

public struct LiveStatusBadge: View {
    public enum StatusType {
        case active
        case standby
        case warning
        case idle
        case custom(Color, String)

        var color: Color {
            switch self {
            case .active: return .green
            case .standby: return .cyan
            case .warning: return .orange
            case .idle: return .secondary
            case .custom(let c, _): return c
            }
        }

        var defaultTitle: String {
            switch self {
            case .active: return tr("运行中", "Active", "実行中")
            case .standby: return tr("就绪", "Ready", "待機中")
            case .warning: return tr("注意", "Warning", "警告")
            case .idle: return tr("未启用", "Inactive", "未有効化")
            case .custom(_, let t): return t
            }
        }
    }

    let status: StatusType
    let customText: String?

    public init(_ status: StatusType, title: String? = nil) {
        self.status = status
        self.customText = title
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)

            Text(customText ?? status.defaultTitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - Native Metric Stat Card

public struct MetricStatCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String?
    let accentColor: Color

    public init(
        icon: String,
        title: String,
        value: String,
        subtitle: String? = nil,
        accentColor: Color = .accentColor
    ) {
        self.icon = icon
        self.title = title
        self.value = value
        self.subtitle = subtitle
        self.accentColor = accentColor
    }

    public var body: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(accentColor)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.headline)
                        .monospacedDigit()
                    if let sub = subtitle {
                        Text(sub)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Section Header

public struct GamingSectionHeader: View {
    let icon: String
    let title: String
    let subtitle: String?
    let accentColor: Color

    public init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        accentColor: Color = .accentColor
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.accentColor = accentColor
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title2.bold())
                .foregroundStyle(accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.title2.bold())
                if let sub = subtitle {
                    Text(sub)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }
}
