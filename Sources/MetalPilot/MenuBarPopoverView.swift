import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MetalPilotCore
#endif

public struct MenuBarPopoverView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedTab: MenuBarTab = .scaling

    public init() {}

    public enum MenuBarTab: String, CaseIterable, Identifiable {
        case scaling
        case metalHUD
        case gameBoost
        case gameLauncher

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .scaling: return "sparkles.tv"
            case .metalHUD: return "chart.xyaxis.line"
            case .gameBoost: return "bolt.fill"
            case .gameLauncher: return "app.badge.checkmark"
            }
        }

        public var titleZh: String {
            switch self {
            case .scaling: return "超分补帧"
            case .metalHUD: return "Metal HUD"
            case .gameBoost: return "游戏加速"
            case .gameLauncher: return "快捷启动"
            }
        }

        public var titleEn: String {
            switch self {
            case .scaling: return "Scaling"
            case .metalHUD: return "Metal HUD"
            case .gameBoost: return "Boost"
            case .gameLauncher: return "Launcher"
            }
        }

        public var titleJa: String {
            switch self {
            case .scaling: return "超解像"
            case .metalHUD: return "Metal HUD"
            case .gameBoost: return "高速化"
            case .gameLauncher: return "起動"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top App Header
            topHeaderView
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 10)

            // Horizontal Tab Bar (Icon Segmented Bar)
            tabBarView
                .padding(.horizontal, 14)
                .padding(.bottom, 10)

            Divider()
                .opacity(0.3)

            // Tab Content Body
            ScrollView {
                VStack(spacing: 10) {
                    switch selectedTab {
                    case .scaling:
                        scalingTabContent
                    case .metalHUD:
                        metalHUDTabContent
                    case .gameBoost:
                        gameBoostTabContent
                    case .gameLauncher:
                        gameLauncherTabContent
                    }
                }
                .padding(12)
            }
            // Let the scroll region absorb the remaining popover height instead of
            // leaving AppKit-owned padding above/below the hosting view.
            .frame(maxHeight: .infinity)

            Divider()
                .opacity(0.3)

            // Bottom Fixed Action Bar (Settings & Quit)
            bottomActionBar
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))
        }
        // Keep the SwiftUI hosting view exactly the same size as the NSPopover.
        // Without an explicit height, AppKit centers the smaller intrinsic view and
        // exposes its own material at the top and bottom edges.
        .frame(width: 380, height: 500, alignment: .top)
        .background(
            VisualEffectBlur(material: .popover, blendingMode: .withinWindow)
        )
    }

    // MARK: - Top Header View

    private var topHeaderView: some View {
        HStack(spacing: 10) {
            Image("MetalPilotLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(tr("MetalPilot", "MetalPilot", "MetalPilot"))
                    .font(.system(size: 13, weight: .bold))
                Text("\(AppVersion.displayString) • Apple Silicon")
                    .font(.system(size: 9, weight: .medium).monospaced())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            LiveStatusBadge(
                model.isScalingActive || model.metalHUDEnabled || model.isGamingFocusActive ? .active : .standby,
                title: model.isScalingActive ? tr("补帧中", "Active", "補正中") : (model.metalHUDEnabled ? "HUD" : tr("待机", "Standby", "待機"))
            )
        }
    }

    // MARK: - Tab Bar (Horizontal Icon Pills)

    private var tabBarView: some View {
        HStack(spacing: 6) {
            ForEach(MenuBarTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.12)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 14, weight: isSelected ? .bold : .medium))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        Text(tr(tab.titleZh, tab.titleEn, tab.titleJa))
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? .primary : .secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Tab 1: Scaling & Frame Gen

    private var scalingTabContent: some View {
        VStack(spacing: 8) {
            // Main Switch Card
            popoverCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("开启画质超分与补帧", "Scaling & Frame Gen", "超解像と動的補フレーム"))
                            .font(.system(size: 12, weight: .bold))
                        Text(tr("快捷键 ⌘⇧T 开关", "Shortcut: ⌘⇧T", "ショートカット: ⌘⇧T"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.isScalingActive },
                        set: { _ in model.toggleScaling() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            // Options Card
            popoverCard {
                VStack(alignment: .leading, spacing: 8) {
                    // Target Window
                    HStack {
                        Text(tr("目标窗口", "Target Window", "対象ウィンドウ"))
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 70, alignment: .leading)
                        Spacer()
                        Picker("", selection: $model.selectedWindowID) {
                            if model.availableWindows.isEmpty {
                                Text(tr("未选择窗口", "None", "未選択")).tag(Optional<CGWindowID>.none)
                            } else {
                                ForEach(model.availableWindows) { win in
                                    Text("\(win.appName)").tag(Optional(win.id))
                                }
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(maxWidth: 180)

                        Button {
                            model.refreshAvailableWindows()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.borderless)
                        .help(tr("刷新窗口列表", "Refresh", "更新"))
                    }

                    Divider().opacity(0.4)

                    // Frame Gen Mode
                    HStack {
                        Text(tr("补帧算法", "Mode", "補フレーム"))
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 70, alignment: .leading)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.configuration.scalingSettings.frameGenMode },
                            set: { var s = model.configuration.scalingSettings; s.frameGenMode = $0; model.updateScalingSettings(s) }
                        )) {
                            ForEach(FrameGenMode.allCases) { mode in
                                Text(tr(mode.titleZh, mode.titleEn, mode.titleJa)).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(maxWidth: 200)
                    }

                    Divider().opacity(0.4)

                    // Anti-Aliasing
                    HStack {
                        Text(tr("抗锯齿", "Anti-Aliasing", "アンチエイリアス"))
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 70, alignment: .leading)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { model.configuration.scalingSettings.aaMode },
                            set: { var s = model.configuration.scalingSettings; s.aaMode = $0; model.updateScalingSettings(s) }
                        )) {
                            ForEach(ScalingAAMode.allCases) { aa in
                                Text(tr(aa.titleZh, aa.titleEn, aa.titleJa)).tag(aa)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .frame(maxWidth: 200)
                    }

                    Divider().opacity(0.4)

                    // CAS Sharpening
                    HStack {
                        Text(tr("CAS 锐化", "CAS Sharpening", "CAS 鮮鋭化"))
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { model.configuration.scalingSettings.casEnabled },
                            set: { var s = model.configuration.scalingSettings; s.casEnabled = $0; model.updateScalingSettings(s) }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Metal HUD

    private var metalHUDTabContent: some View {
        VStack(spacing: 8) {
            // Global HUD Toggle
            popoverCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("全局 Metal HUD 监视器", "Global Metal HUD", "全局 Metal HUD モニター"))
                            .font(.system(size: 12, weight: .bold))
                        Text(tr("系统环境注入 (MTL_HUD_ENABLED)", "Inject system-wide", "システム全体に環境変数を注入"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.metalHUDEnabled },
                        set: { model.setMetalHUD($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            // Presets Card
            popoverCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tr("HUD 预设方案", "HUD Presets", "HUD プリセット"))
                        .font(.system(size: 11, weight: .bold))

                    HStack(spacing: 6) {
                        presetPill(title: tr("精简", "Minimal", "最小"), preset: .minimal)
                        presetPill(title: tr("均衡", "Balanced", "バランス"), preset: .balanced)
                        presetPill(title: tr("完整", "Complex", "完全"), preset: .complex)
                    }

                    Divider().opacity(0.4)

                    // Quick Sliders
                    HStack {
                        Text(tr("缩放", "Scale", "倍率"))
                            .font(.system(size: 10))
                            .frame(width: 38, alignment: .leading)
                        Slider(value: Binding(
                            get: { model.configuration.metalHUDOptions.scale },
                            set: { var o = model.configuration.metalHUDOptions; o.scale = $0; model.updateMetalHUDOptions(o) }
                        ), in: 0.1...1.0)
                        .controlSize(.mini)
                        Text("\(Int(model.configuration.metalHUDOptions.scale * 100))%")
                            .font(.system(size: 9).monospaced())
                            .frame(width: 30, alignment: .trailing)
                    }

                    HStack {
                        Text(tr("透明度", "Opacity", "不透明"))
                            .font(.system(size: 10))
                            .frame(width: 38, alignment: .leading)
                        Slider(value: Binding(
                            get: { model.configuration.metalHUDOptions.opacity },
                            set: { var o = model.configuration.metalHUDOptions; o.opacity = $0; model.updateMetalHUDOptions(o) }
                        ), in: 0.0...1.0)
                        .controlSize(.mini)
                        Text("\(Int(model.configuration.metalHUDOptions.opacity * 100))%")
                            .font(.system(size: 9).monospaced())
                            .frame(width: 30, alignment: .trailing)
                    }
                }
            }

            // Quick restart button
            Button {
                StatusBarController.shared.closePopover()
                MenuCommandCoordinator.shared.reopenMainWindow()
                model.openMetalHUDProcessManager()
            } label: {
                Label(tr("排查并重启冲突进程 (Steam/Wine)…", "Check Interfering Processes…", "競合プロセスを確認・再起動…"), systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func presetPill(title: String, preset: MetalHUDPreset) -> some View {
        let isSelected = model.currentMetalHUDPreset() == preset
        return Button(title) {
            model.applyMetalHUDPreset(preset)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? Color.accentColor : nil)
        .controlSize(.mini)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Tab 3: Game Boost

    private var gameBoostTabContent: some View {
        VStack(spacing: 8) {
            // Focus Anti-Sleep Toggle
            popoverCard {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("游戏专注防休眠", "Gaming Focus (Anti-Sleep)", "ゲーム集中・スリープ防止"))
                            .font(.system(size: 12, weight: .bold))
                        Text(tr("Caffeinate 守护防降频防息屏", "Caffeinate keeps display & max clock", "Caffeinateによるスリープ・消灯抑止"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.isGamingFocusActive },
                        set: { _ in model.toggleGamingFocus() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }
            }

            // Quick Boost Actions Card
            popoverCard {
                VStack(spacing: 6) {
                    // Wine Priority
                    Button {
                        model.increaseCrossOverPriority()
                    } label: {
                        HStack {
                            Image(systemName: "bolt.badge.clock.fill")
                                .foregroundStyle(.orange)
                            Text(tr("优化 Wine 进程优先级 (Renice -20)", "Boost Wine Priority (Renice -20)", "Wine プロセス優先度最適化"))
                                .font(.system(size: 11))
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // SteamDeck Spoof
                    let isSteamDeck = model.configuration.hostnameBackup != nil
                    Button {
                        model.toggleSteamDeck()
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.2.swap")
                                .foregroundStyle(isSteamDeck ? .purple : .secondary)
                            Text(isSteamDeck ? tr("恢复原生 Mac 主机名", "Restore Native Hostname", "Mac標準ホスト名に復元") : tr("切换至 SteamDeck 反作弊伪装", "Enable SteamDeck Spoofing", "SteamDeck 偽装を有効化"))
                                .font(.system(size: 11))
                            Spacer()
                            if isSteamDeck {
                                Circle().fill(Color.purple).frame(width: 6, height: 6)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // HoYoGames Assistant
                    Button {
                        if model.isHoYoAssistantRunning {
                            model.cancelHoYoAssistant()
                        } else {
                            model.startHoYoAssistant()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "gamecontroller.fill")
                                .foregroundStyle(model.isHoYoAssistantRunning ? .green : .purple)
                            Text(model.isHoYoAssistantRunning ? tr("取消 HoYoGames 启动辅助", "Cancel HoYo Assistant", "起動補助をキャンセル") : tr("HoYoGames 启动辅助 (15s hosts 代理)", "HoYoGames Launch Assistant", "HoYoGames 起動補助 (15秒)"))
                                .font(.system(size: 11))
                            Spacer()
                            if model.isHoYoAssistantRunning {
                                ProgressView().controlSize(.mini)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Tab 4: Game Launcher (Pre-selected Library)

    private var gameLauncherTabContent: some View {
        VStack(spacing: 8) {
            // Control row
            HStack {
                Button {
                    model.addAppToHUDList()
                } label: {
                    Label(tr("添加应用", "Add App", "アプリ追加"), systemImage: "plus")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)

                Spacer()

                Button(tr("全选", "All", "全選択")) {
                    model.selectedHUDAppPaths = Set(model.configuration.recentMetalHUDApps.map(\.path))
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button(tr("清空", "Clear", "解除")) {
                    model.selectedHUDAppPaths.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }

            if model.configuration.recentMetalHUDApps.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 26))
                        .foregroundStyle(.secondary)
                    Text(tr("暂未添加游戏应用", "No games in library", "登録ゲームがありません"))
                        .font(.system(size: 11, weight: .bold))
                    Text(tr("点击上方「添加应用」预选常用游戏", "Click 'Add App' above to preselect games", "上のボタンからゲームを登録"))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.configuration.recentMetalHUDApps) { app in
                            popoverGameRow(app)
                        }
                    }
                }
                .frame(maxHeight: 200)

                // Batch launch button
                Button {
                    let targets = Array(model.selectedHUDAppPaths)
                    StatusBarController.shared.closePopover()
                    model.launchSelectedHUDApps(targets)
                } label: {
                    Label(
                        tr("启动勾选游戏 (\(model.selectedHUDAppPaths.count))", "Launch Checked (\(model.selectedHUDAppPaths.count))", "チェックしたゲームを起動 (\(model.selectedHUDAppPaths.count))"),
                        systemImage: "play.fill"
                    )
                    .font(.system(size: 11, weight: .bold))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.selectedHUDAppPaths.isEmpty)
                .controlSize(.small)
            }
        }
    }

    private func popoverGameRow(_ app: RecentMetalHUDApp) -> some View {
        let isSelected = model.selectedHUDAppPaths.contains(app.path)
        let hasCustomProfile = model.profileForApp(path: app.path) != nil

        return HStack(spacing: 8) {
            // Checkbox
            Button {
                if isSelected {
                    model.selectedHUDAppPaths.remove(app.path)
                } else {
                    model.selectedHUDAppPaths.insert(app.path)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 12))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                .resizable()
                .frame(width: 20, height: 20)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }

            Spacer()

            if app.importedPreset != nil {
                // Imported preset takes priority over the custom/global profile.
                Text("◆")
                    .font(.system(size: 8))
                    .foregroundStyle(.orange)
                    .help(tr("使用导入的外部 HUD 预设", "Using imported external HUD preset", "外部 HUD プリセットを使用中"))
            } else if hasCustomProfile {
                Text("★")
                    .font(.system(size: 8))
                    .foregroundStyle(.green)
            }

            // Single direct launch button
            Button {
                StatusBarController.shared.closePopover()
                model.launchRecordedAppWithMetalHUD(app.path)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help(tr("独立注入并启动此游戏", "Launch this game with HUD", "このゲームを起動"))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }

    // MARK: - Custom Card Container Helper

    private func popoverCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
    }

    // MARK: - Bottom Fixed Action Bar

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            // Open Main Interface / Settings
            Button {
                StatusBarController.shared.closePopover()
                MenuCommandCoordinator.shared.reopenMainWindow()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                    Text(tr("打开主界面", "Open MetalPilot", "メイン画面を開く"))
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            // Quit App
            Button {
                StatusBarController.shared.closePopover()
                MenuCommandCoordinator.shared.quitApplication()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                    Text(tr("退出", "Quit", "終了"))
                        .font(.system(size: 11, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}
