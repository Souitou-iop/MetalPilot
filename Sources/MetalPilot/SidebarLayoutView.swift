import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MetalPilotCore
#endif

public struct SidebarLayoutView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedCategory: NavigationCategory = .overview

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            sidebarView
                .frame(width: 220)
                .background(
                    VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)
                )
                .overlay(
                    Rectangle()
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 0.5),
                    alignment: .trailing
                )

            // Right Main Content Panel
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    contentView
                        .transition(.opacity)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.2), value: selectedCategory)
        }
    }

    // MARK: - Sidebar View

    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // App Branding Title in Sidebar
            HStack(spacing: 10) {
                Image("MetalPilotLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(tr("MetalPilot", "MetalPilot", "MetalPilot"))
                        .font(.headline)
                    Text(AppVersion.displayString)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider().padding(.horizontal, 14)

            // Navigation Items
            VStack(spacing: 4) {
                ForEach(NavigationCategory.allCases) { item in
                    sidebarItemRow(item)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Bottom Status Pill
            bottomStatusSummary
                .padding(12)
        }
    }

    private func sidebarItemRow(_ item: NavigationCategory) -> some View {
        let isSelected = selectedCategory == item
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedCategory = item
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.iconName)
                    .font(.system(size: 15, weight: isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 22)

                Text(tr(item.titleZh, item.titleEn, item.titleJa))
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if item == .metalHUD && model.metalHUDEnabled {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                } else if item == .system && model.configuration.hostnameBackup != nil {
                    Circle()
                        .fill(Color.purple)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var bottomStatusSummary: some View {
        HStack(spacing: 8) {
            LiveStatusBadge(
                model.metalHUDEnabled ? .active : .standby,
                title: model.metalHUDEnabled ? tr("HUD 启用中", "HUD Active", "HUD 有効") : tr("MetalPilot 就绪", "MetalPilot Ready", "MetalPilot 待機中")
            )
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }

    // MARK: - Content View Switcher

    @ViewBuilder
    private var contentView: some View {
        switch selectedCategory {
        case .overview:
            OverviewSectionView { target in
                withAnimation { selectedCategory = target }
            }
        case .frameGen:
            FrameGenSectionView()
        case .metalHUD:
            MetalHUDSectionView()
        case .gameBoost:
            GameBoostSectionView()
        case .storage:
            StorageSectionView()
        case .system:
            SystemSectionView()
        case .about:
            AboutSectionView()
        }
    }
}

// MARK: - Native Visual Effect Blur Helper

public struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State = .active

    public func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    public func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
