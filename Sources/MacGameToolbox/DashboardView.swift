#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif
import AppKit
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedCategory: NavigationCategory? = .overview
    @State private var nativeGlassEnabled = NSApp.isActive
    @State private var showingMetalHUDApps = false
    @State private var showingMetalHUDTuner = false
    @State private var displayedStatus = TaskStatus()
    @State private var isStatusPanelVisible = false

    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .background(WindowAppearanceConfigurator(nativeGlassEnabled: $nativeGlassEnabled, colorScheme: colorScheme, isEnabled: false))
        .sheet(isPresented: $model.showingDiskManager) { DiskManagerView().environmentObject(model) }
        .sheet(isPresented: $model.showingChangelog) { ChangelogView() }
        .sheet(isPresented: $model.showingTutorials) { TutorialsView() }
        .sheet(isPresented: $model.showingProcessSelection) { ProcessSelectionView().environmentObject(model) }
        .sheet(isPresented: $model.showingMetalHUDProcessManager) { MetalHUDProcessManagerView().environmentObject(model) }
        .sheet(isPresented: $showingMetalHUDTuner) { MetalHUDTunerView().environmentObject(model) }
        .sheet(isPresented: $model.showingIOSHUDLauncher) { IOSHUDLauncherSheetView().environmentObject(model) }
        .alert(cacheAlertTitle, isPresented: $model.showingCacheConfirmation) {
            Button(tr("取消", "Cancel"), role: .cancel) {}
            if model.isCacheCleanupBlockedByIncompleteScan {
                Button(tr("打开系统设置", "Open System Settings")) { model.openFullDiskAccessSettings() }
                Button(tr("重新扫描", "Scan Again")) { model.prepareCacheScan() }
            } else {
                Button(model.cacheConfirmationStage == 1 ? tr("继续", "Continue") : tr("确认删除", "Delete"), role: model.configuration.excludesSensitiveCacheFiles ? nil : .destructive) { model.confirmCacheCleaning() }
            }
        } message: { Text(cacheAlertMessage) }
        .alert(tr("检测到旧版辅助服务", "Legacy Helper Detected", "旧ヘルパーサービスを検出"), isPresented: $model.legacyHelperMigrationPending) {
            Button(tr("立即迁移", "Migrate Now", "今すぐ移行")) { model.migrateLegacyHelper() }
            Button(tr("保留旧服务（双软件共存）", "Keep Legacy Service (Side-by-Side)", "旧サービスを残す（共存）")) { model.keepLegacyHelperCoexistence() }
            Button(tr("稍后", "Later", "後で"), role: .cancel) {}
        } message: {
            Text(tr("系统后台仍注册着旧版辅助服务 macgametoolbox.helper。立即迁移将卸载并清理旧服务（需一次管理员授权），后台列表仅保留 metalpilot.helper；选择保留则新旧服务共存、互不影响，适合同时保留新旧两个应用的用户，之后可在系统页随时迁移。",
                    "The legacy helper macgametoolbox.helper is still registered. Migrating now uninstalls it (one admin authorization) and keeps only metalpilot.helper; choosing Keep runs both services side by side for users who retain the old app, and migration stays available on the System page.",
                    "旧ヘルパー macgametoolbox.helper が登録されています。今すぐ移行すると旧サービスをアンインストールし（管理者認証一度）、metalpilot.helper のみが残ります。残すを選ぶと新旧両方が共存し、旧アプリ併用ユーザーに適しています。移行はシステムページからいつでも実行できます。"))
        }
        .alert(tr("当前为双软件共存模式", "Side-by-Side Mode Active", "共存モードが有効です"), isPresented: $model.showingCoexistenceRepairChoice) {
            Button(tr("仅重新注册（保留旧服务）", "Re-register Only (Keep Legacy)", "再登録のみ（旧サービスを残す）")) { model.cleanAllLegacyHelpersAndRepair() }
            Button(tr("迁移并清理旧服务", "Migrate & Clean Legacy", "移行して旧サービスを削除")) { model.migrateLegacyHelper() }
            Button(tr("取消", "Cancel", "キャンセル"), role: .cancel) {}
        } message: {
            Text(tr("请选择如何处理旧版辅助服务 macgametoolbox.helper。迁移后系统后台仅保留 metalpilot.helper。",
                    "Choose how to handle the legacy macgametoolbox.helper service. After migration only metalpilot.helper remains in the background list.",
                    "旧ヘルパー macgametoolbox.helper の扱いを選択してください。移行後はバックグラウンドに metalpilot.helper のみが残ります。"))
        }
        .environment(\.colorScheme, colorScheme)
        .environment(\.dashboardColorScheme, colorScheme)
        .environment(\.nativeGlassEnabled, false)
        .environment(\.usesLiquidGlassUI, false)
        .onAppear {
            MenuCommandCoordinator.shared.install(model: model)
            guard model.status.phase != .idle else { return }
            displayedStatus = model.status
            isStatusPanelVisible = true
        }
        .onChange(of: model.status) { _, newStatus in
            if newStatus.phase == .idle {
                withAnimation(.easeInOut(duration: 0.45)) {
                    isStatusPanelVisible = false
                }
            } else {
                displayedStatus = newStatus
                withAnimation(.easeInOut(duration: 0.45)) {
                    isStatusPanelVisible = true
                }
            }
        }
    }

    private var statusPanel: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: statusIcon)
                Text(displayedStatus.message).font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)
            if let progress = displayedStatus.progress {
                ProgressView(value: progress)
                    .tint(.purple)
                    .frame(minWidth: 160)
            }
            Spacer(minLength: 8)
            if model.isHoYoAssistantRunning {
                Button(tr("取消并恢复 hosts", "Cancel and restore hosts")) { model.cancelHoYoAssistant() }
            }
            Text(AppLanguage.phase(displayedStatus.phase))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .liquidGlassButtonStyle()
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .liquidGlassPanel(cornerRadius: 12, colorScheme: colorScheme, usesLiquidGlassUI: false, nativeGlassEnabled: false)
    }

    @ViewBuilder private var featureCards: some View {
        FeatureCard(icon: "gauge.with.dots.needle.67percent", title: tr("MetalHUD 性能监视器", "MetalHUD Performance Monitor"), subtitle: tr("开发者工具，可以查看游戏帧率等信息，也可以帮助你找到游戏异常的原因", "A developer tool for viewing game frame rates and diagnosing game issues")) {
            HStack(spacing: 8) {
                Toggle(tr("全局启用", "Enable globally"), isOn: Binding(get: { model.metalHUDEnabled }, set: { value in model.setMetalHUD(value) })).toggleStyle(.switch).fixedSize(horizontal: true, vertical: false)
                Spacer()
                Button(tr("进程排查", "Processes")) { model.openMetalHUDProcessManager() }
                Button(tr("调节", "Tune")) { showingMetalHUDTuner = true }
                Button(tr("对单个 App 启用", "Enable for one app")) {
                    if model.configuration.recentMetalHUDApps.isEmpty {
                        model.launchAppWithMetalHUD()
                    } else {
                        showingMetalHUDApps.toggle()
                    }
                }
                .popover(isPresented: $showingMetalHUDApps, arrowEdge: .bottom) {
                    MetalHUDAppMenu(isPresented: $showingMetalHUDApps).environmentObject(model)
                }
            }
        }
        FeatureCard(icon: "gamecontroller.fill", title: tr("HoYoGames 启动帮助", "HoYoGames Launch Assistant"), subtitle: tr("此选项可以帮助你启动HoYoGames，点击“开始运行”后需要在指定时间内打开游戏", "Helps launch HoYoGames; open the game within the selected time after clicking Start")) {
            HStack(alignment: .bottom) {
                Button(tr("开始运行", "Start")) { model.startHoYoAssistant() }
                    .liquidGlassButton(prominent: true)
                Spacer()
                Picker(tr("等待时间", "Wait time"), selection: Binding(get: { model.configuration.hoYoWaitSeconds }, set: { model.setHoYoWaitSeconds($0) })) {
                    ForEach([10, 15, 20], id: \.self) { Text("\($0) \(tr("秒", "sec"))").tag($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 92)
            }
        }
        FeatureCard(icon: "bolt.fill", title: tr("提高CrossOver优先级", "Increase CrossOver Priority"), subtitle: tr("检测并提高Windows游戏优先级", "Detect and increase Windows game priority")) {
            HStack(alignment: .bottom) {
                Button(tr("检测并优化", "Detect and optimize")) { model.increaseCrossOverPriority() }
                Spacer()
                Button(tr("手动选择进程", "Select processes")) { model.loadProcessesForManualSelection() }
            }
        }
        FeatureCard(icon: "externaldrive.fill", title: tr("将磁盘挂载到指定路径", "Mount a Disk at a Specified Path"), subtitle: tr("此方法可自定义外接磁盘的挂载路径，可将部分原本不可放在外接磁盘的游戏资源转移到外接磁盘以节省内置磁盘存储空间", "Customize an external disk's mount path and move supported game resources there to save internal storage space")) {
            HStack(alignment: .bottom) {
                Button(tr("管理磁盘", "Manage volumes")) { model.loadDisks() }
                Spacer()
                Button(tr("恢复上次挂载", "Restore last mount")) { model.restorePreviousMounts() }
            }
        }
        FeatureCard(icon: "trash.fill", title: tr("缓存与日志一键清理", "One-click Cache and Log Cleanup"), subtitle: tr("默认仅清理用户缓存和日志；关闭敏感文件排除后将执行高风险完整清理", "Cleans user caches and logs by default; disabling sensitive-file exclusion performs the high-risk full cleanup")) {
            HStack(alignment: .bottom) {
                Button(tr("一键清理", "Clean now"), role: .destructive) { model.prepareCacheScan() }
                Spacer()
                Toggle(tr("排除敏感文件", "Exclude sensitive files"), isOn: Binding(get: { model.configuration.excludesSensitiveCacheFiles }, set: { model.setExcludesSensitiveCacheFiles($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        }
        FeatureCard(icon: "rectangle.2.swap", title: tr("切换到SteamDeck模式", "Switch to SteamDeck Mode"), subtitle: tr("部分游戏反作弊只给SteamDeck后门，伪装成SteamDeck让Mac也能玩", "Some anti-cheat systems allow SteamDeck; impersonating one may let the game run on Mac")) {
            Button(tr("切换模式", "Toggle mode")) { model.toggleSteamDeck() }
        }
        FeatureCard(icon: "book.pages.fill", title: tr("教程总导航", "Tutorial Hub"), subtitle: tr("Mac 游戏与 CrossOver 教程", "Mac gaming and CrossOver tutorials")) {
            Button(tr("打开导航", "Open hub")) { model.showingTutorials = true }
        }
        FeatureCard(icon: "clock.arrow.circlepath", title: tr("更新日志", "Changelog"), subtitle: tr("查看版本变化", "Review version changes")) {
            Button(tr("查看", "View")) { model.showingChangelog = true }
        }
    }

    private var sidebarContent: some View {
        List(NavigationCategory.allCases, selection: $selectedCategory) { category in
            NavigationLink(value: category) {
                Label(tr(category.titleZh, category.titleEn, category.titleJa), systemImage: category.iconName)
                    .badge(badgeForCategory(category))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
        .safeAreaInset(edge: .bottom) {
            sidebarFooter
        }
    }

    private var detailContent: some View {
        ZStack(alignment: .bottom) {
            background
                .transaction { transaction in
                    transaction.animation = nil
                }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedCategory ?? .overview {
                    case .overview:
                        OverviewSectionView { target in
                            selectedCategory = target
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
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusPanel
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .compositingGroup()
                .opacity(isStatusPanelVisible ? 1 : 0)
                .allowsHitTesting(isStatusPanelVisible)
                .accessibilityHidden(!isStatusPanelVisible)
        }
        .navigationTitle(tr("MetalPilot", "MetalPilot", "MetalPilot"))
    }

    private var sidebarFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(model.metalHUDEnabled ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)
            Text(model.metalHUDEnabled ? tr("Metal HUD 已开启", "Metal HUD Active", "Metal HUD 有効") : tr("MetalPilot 就绪", "MetalPilot Ready", "MetalPilot 準備完了"))
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private func badgeForCategory(_ category: NavigationCategory) -> String? {
        if category == .metalHUD && model.metalHUDEnabled {
            return "ON"
        } else if category == .system && model.configuration.hostnameBackup != nil {
            return "Deck"
        }
        return nil
    }

    private var statusIcon: String {
        switch displayedStatus.phase {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        case .cancelled: "minus.circle.fill"
        case .awaitingAuthorization: "lock.shield.fill"
        default: "gearshape.2.fill"
        }
    }

    private var backgroundColors: [Color] {
        colorScheme == .dark
            ? [GamingTheme.bgDeepDark, GamingTheme.bgSurfaceDark]
            : [Color(red: 0.94, green: 0.96, blue: 1.0), Color(red: 0.98, green: 0.94, blue: 1.0)]
    }

    @ViewBuilder private var background: some View {
        GeometryReader { proxy in
            LinearGradient(colors: backgroundColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }

    private var cacheAlertTitle: String {
        if model.isCacheCleanupBlockedByIncompleteScan { return tr("需要完全磁盘访问权限", "Full Disk Access Required") }
        if model.configuration.excludesSensitiveCacheFiles { return tr("准备清理", "Ready to Clean") }
        return model.cacheConfirmationStage == 1 ? tr("高风险操作", "High Risk") : tr("最终确认", "Final Confirmation")
    }
    private var cacheAlertMessage: String {
        guard let scan = model.cacheScan else { return "" }
        let size = ByteCountFormatter.string(fromByteCount: Int64(scan.estimatedBytes), countStyle: .file)
        if !scan.inaccessibleTargets.isEmpty {
            let paths = scan.inaccessibleTargets.prefix(3)
                .map { "\($0.path.path)：\($0.reason)" }
                .joined(separator: "\n")
            let suffix = scan.inaccessibleTargets.count > 3 ? tr("\n……以及其他项目", "\n…and other items") : ""
            if model.configuration.excludesSensitiveCacheFiles {
                return tr(
                    "扫描不完整：\(scan.inaccessibleTargets.count) 个缓存目录无法读取，已统计大小 \(size)。仍可继续安全清理（仅用户目录，共 \(scan.userTargets.count) 个）。如需完整清理，请授予完全磁盘访问权限后重新扫描：\n\(paths)\(suffix)",
                    "Scan incomplete: \(scan.inaccessibleTargets.count) cache item(s) could not be read; readable size is \(size). You can still continue the safe cleanup (\(scan.userTargets.count) user folder(s) only). For a full cleanup, grant Full Disk Access and scan again:\n\(paths)\(suffix)"
                )
            }
            return tr(
                "发现 \(scan.inaccessibleTargets.count) 个无法读取的缓存目录，已统计大小 \(size)。完全清理需要读取系统目录，请在系统设置中授予完全磁盘访问权限后重新扫描：\n\(paths)\(suffix)",
                "Found \(scan.inaccessibleTargets.count) unreadable cache item(s); readable size is \(size). The full cleanup also reads system directories, so grant Full Disk Access in System Settings, then scan again:\n\(paths)\(suffix)"
            )
        }
        if model.configuration.excludesSensitiveCacheFiles {
            return tr("预计清理 \(size)，点击继续进行清理", "About \(size) will be cleaned. Click Continue to proceed.")
        }
        if model.cacheConfirmationStage == 1 {
            return tr("预计删除 \(size)，涉及 \(scan.userTargets.count) 个用户目录和系统日志。登录状态及游戏缓存可能丢失。", "About \(size) will be deleted across \(scan.userTargets.count) user folders and system logs. Login state and game caches may be lost.")
        }
        return tr("此操作不可撤销。首次使用时会启用系统辅助服务。确认永久删除这些缓存和日志吗？", "This cannot be undone. The system helper will be enabled on first use. Permanently delete these caches and logs?")
    }
}

private struct MetalHUDAppMenu: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool
    @State private var launchingPath: String?

    private let columns = Array(repeating: GridItem(.fixed(88), spacing: 14), count: 4)

    var body: some View {
        VStack(spacing: 16) {
            Text(tr("最近使用 MetalHUD 打开的 App", "Recently opened with MetalHUD"))
                .font(.headline)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(model.configuration.recentMetalHUDApps) { app in
                    Button {
                        launch(app)
                    } label: {
                        VStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                .resizable()
                                .scaledToFit()
                                .frame(width: 58, height: 58)
                                .scaleEffect(launchingPath == app.path ? 1.35 : 1)
                                .opacity(launchingPath == app.path ? 0 : 1)
                            Text(app.displayName)
                                .font(.caption)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                                .frame(width: 84)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(tr("移除", "Remove"), role: .destructive) { model.removeRecentMetalHUDApp(app) }
                    }
                    .transaction { $0.animation = .easeInOut(duration: 0.22) }
                }
            }
            Divider()
            Button {
                isPresented = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { model.launchAppWithMetalHUD() }
            } label: {
                Label(tr("其他 App", "Other App"), systemImage: "plus.app")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(20)
        .frame(width: 430)
    }

    private func launch(_ app: RecentMetalHUDApp) {
        withAnimation(.easeInOut(duration: 0.22)) { launchingPath = app.path }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            isPresented = false
            launchingPath = nil
            model.launchRecordedAppWithMetalHUD(app.path)
        }
    }
}

private struct MetalHUDTunerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var advancedPositionExpanded = false
    @State private var advancedExpanded = false
    @State private var showingResetConfirm = false

    private let alignmentOptions: [(raw: String, zh: String, en: String)] = [
        ("topleft", "左上", "Top Left"),
        ("topcenter", "中上", "Top Center"),
        ("topright", "右上", "Top Right"),
        ("centerleft", "左中", "Center Left"),
        ("centered", "居中", "Centered"),
        ("centerright", "右中", "Center Right"),
        ("bottomleft", "左下", "Bottom Left"),
        ("bottomcenter", "中下", "Bottom Center"),
        ("bottomright", "右下", "Bottom Right")
    ]

    private var options: MetalHUDOptions { model.configuration.metalHUDOptions }

    private var opacityBinding: Binding<Double> {
        Binding(
            get: { options.opacity },
            set: { value in
                var o = options
                o.opacity = value
                model.updateMetalHUDOptions(o)
            }
        )
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { options.scale },
            set: { value in
                var o = options
                o.scale = value
                model.updateMetalHUDOptions(o)
            }
        )
    }

    private var alignmentBinding: Binding<String> {
        Binding(
            get: { options.alignment },
            set: { value in
                var o = options
                o.alignment = value
                model.updateMetalHUDOptions(o)
            }
        )
    }

    private func intOptionalBinding(_ keyPath: WritableKeyPath<MetalHUDOptions, Int?>, default defaultValue: Int) -> Binding<Int> {
        Binding(
            get: { options[keyPath: keyPath] ?? defaultValue },
            set: { value in
                var o = options
                o[keyPath: keyPath] = value
                model.updateMetalHUDOptions(o)
            }
        )
    }

    private func clearIntOptional(_ keyPath: WritableKeyPath<MetalHUDOptions, Int?>) {
        var o = options
        o[keyPath: keyPath] = nil
        model.updateMetalHUDOptions(o)
    }

    private func boolBinding(_ keyPath: WritableKeyPath<MetalHUDOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { options[keyPath: keyPath] },
            set: { value in
                var o = options
                o[keyPath: keyPath] = value
                model.updateMetalHUDOptions(o)
            }
        )
    }

    private func elementBinding(_ el: MetalHUDElement) -> Binding<Bool> {
        Binding(
            get: { options.elements.contains(el.raw) },
            set: { on in
                var o = options
                if on {
                    if !o.elements.contains(el.raw) { o.elements.append(el.raw) }
                } else {
                    o.elements.removeAll { $0 == el.raw }
                }
                model.updateMetalHUDOptions(o)
            }
        )
    }

    private var opacityPercentage: Int { Int((options.opacity * 100).rounded()) }
    private var scalePercentage: Int { Int((options.scale * 100).rounded()) }
    private var selectedElementCount: Int { options.elements.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(tr("MetalHUD 调节器", "MetalHUD Tuner"))
                    .font(.title2.bold())
                Spacer()
                Button(tr("导入", "Import")) { model.importMetalHUDOptions() }
                    .controlSize(.small)
                Button(tr("导出", "Export")) { model.exportMetalHUDOptions() }
                    .controlSize(.small)
                Button(tr("重置全部", "Reset All")) { showingResetConfirm = true }
                    .controlSize(.small)
                Button(tr("完成", "Done")) { dismiss() }
            }
            Text(tr("以下为 macOS 支持的全部 HUD 选项。未设置的项使用系统默认。",
                     "All HUD options supported by macOS. Unset items use system defaults."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    appearanceSection
                    elementsSection
                    Divider()
                    presetsSection
                    Divider()
                    logsSection
                    advancedSection
                }
                .padding(.bottom, 4)
                .padding(.horizontal, 28)
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
                Text(tr("修改将在下次启动应用时生效", "Changes take effect next launch"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(tr("排查运行中进程", "Check Processes")) {
                    model.openMetalHUDProcessManager()
                }
                .controlSize(.small)
            }
        }
        .padding(22)
        .frame(width: 560, height: 660)
        .confirmationDialog(
            tr("确定要重置全部 Metal HUD 配置吗？", "Reset all Metal HUD settings?"),
            isPresented: $showingResetConfirm,
            titleVisibility: .visible
        ) {
            Button(tr("重置", "Reset"), role: .destructive) { model.resetMetalHUDOptions() }
            Button(tr("取消", "Cancel"), role: .cancel) {}
        } message: {
            Text(tr("所有外观、指标、日志与高级设置将恢复为默认值。", "All appearance, metrics, logs and advanced settings will return to defaults."))
        }
    }

    @ViewBuilder
    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(tr("外观", "Appearance"))
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text(tr("透明度", "Opacity"))
                        .rowTitleStyle()
                    Spacer()
                    Slider(value: opacityBinding, in: 0...1, step: 0.05)
                        .frame(maxWidth: 180)
                    Text("\(opacityPercentage)%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    InfoHint(text: tr("调整 HUD 覆盖层的透明度。1.0 为完全不透明，0.0 为完全透明。", "Adjust the HUD overlay opacity. 1.0 is fully opaque, 0.0 is fully transparent."))
                }
                HStack(spacing: 8) {
                    Text(tr("缩放", "Scale"))
                        .rowTitleStyle()
                    Spacer()
                    Slider(value: scaleBinding, in: 0...1, step: 0.05)
                        .frame(maxWidth: 180)
                    Text("\(scalePercentage)%")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    InfoHint(text: tr("HUD 大小，按可绘制宽度百分比。默认 0.2，最小宽度 300 像素。", "HUD size as percentage of drawable width. Default 0.2, min 300px."))
                }
                HStack(spacing: 8) {
                    Text(tr("对齐", "Alignment"))
                        .rowTitleStyle()
                    Spacer()
                    Picker("", selection: alignmentBinding) {
                        ForEach(alignmentOptions, id: \.raw) { option in
                            Text(tr(option.zh, option.en)).tag(option.raw)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 150)
                    InfoHint(text: tr("HUD 在窗口中的位置。", "Position of the HUD in the window."))
                }
            }
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                collapsibleHeader(
                    title: tr("高级", "Advanced"),
                    isExpanded: advancedPositionExpanded
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { advancedPositionExpanded.toggle() }
                }
                if advancedPositionExpanded {
                    VStack(spacing: 8) {
                        intOptionalPositionRow(
                            title: tr("位置 X", "Position X"),
                            binding: intOptionalBinding(\.positionX, default: 0),
                            isSet: options.positionX != nil,
                            onClear: { clearIntOptional(\.positionX) }
                        )
                        intOptionalPositionRow(
                            title: tr("位置 Y", "Position Y"),
                            binding: intOptionalBinding(\.positionY, default: 0),
                            isSet: options.positionY != nil,
                            onClear: { clearIntOptional(\.positionY) }
                        )
                    }
                    .padding(.leading, 16)
                    .padding(.top, 2)
                }
            }
        }
    }

    @ViewBuilder
    private func intOptionalPositionRow(title: String, binding: Binding<Int>, isSet: Bool, onClear: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .rowTitleStyle()
            Spacer()
            TextField("", value: binding, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
            if isSet {
                Button(tr("清除", "Clear")) { onClear() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var elementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(tr("指标列表", "Metrics"))
            HStack(spacing: 10) {
                Button(tr("全选", "Select All")) {
                    var o = options
                    o.elements = MetalHUDElement.allElements.map(\.raw)
                    model.updateMetalHUDOptions(o)
                }
                Button(tr("清空", "Clear")) {
                    var o = options
                    o.elements = []
                    model.updateMetalHUDOptions(o)
                }
                Spacer()
                Text(tr("已选 \(selectedElementCount) 项", "\(selectedElementCount) selected"))
                    .font(.caption)
                    .foregroundStyle(selectedElementCount > 0 ? .primary : .secondary)
                    .monospacedDigit()
                    .frame(width: 90, alignment: .trailing)
                    .lineLimit(1)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], alignment: .leading, spacing: 8) {
                ForEach(MetalHUDElement.allElements, id: \.raw) { el in
                    HStack(spacing: 4) {
                        Toggle(tr(el.zh, el.en), isOn: elementBinding(el))
                            .toggleStyle(.checkbox)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        InfoHint(text: tr(el.hintZh, el.hintEn))
                    }
                }
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var logsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("日志与性能", "Logs & Performance"))
                    .font(.headline)
                Spacer()
                Button(tr("打开控制台", "Open Console")) { model.openConsoleApp() }
                    .controlSize(.small)
                Button(tr("导出近期日志", "Export Recent")) { model.exportRecentHUDLogs() }
                    .controlSize(.small)
            }
            Text(tr("打开控制台：启动 Console.app，手动搜索「metal-hud」查看实时日志。导出近期日志：将最近 10 分钟的 HUD 日志导出为 .log 文件并自动打开。",
                    "Open Console: launches Console.app, manually search \"metal-hud\" for live logs. Export Recent: exports the last 10 minutes of HUD logs as a .log file and opens it."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("日志", "Logs"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    toggleRow(tr("帧统计日志", "Frame statistics log"), boolBinding(\.logEnabled),
                              tr("将每帧的性能统计输出到系统统一日志（subsystem: com.apple.metal.hud），可在控制台 App 中过滤查看。", "Logs per-frame statistics to the unified logging system (subsystem: com.apple.metal.hud). View in Console app."),
                              dependency: !model.metalHUDEnabled ? tr("需启用 HUD", "Needs HUD") : nil)
                    toggleRow(tr("着色器编译日志", "Shader compile log"), boolBinding(\.shaderLogEnabled),
                              tr("记录着色器编译活动到系统统一日志，帮助定位编译耗时问题。", "Logs shader compilation activity to the unified logging system to help diagnose compile-time costs."),
                              dependency: !model.metalHUDEnabled ? tr("需启用 HUD", "Needs HUD") : nil)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("追踪", "Tracking"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    toggleRow(tr("编码器 GPU 时间追踪", "Encoder GPU time tracking"), boolBinding(\.encoderTimingEnabled),
                              tr("开启编码器级 GPU 时间追踪，是 GPU 时间线、高占用命令缓冲区/编码器等指标的前提。", "Enable encoder-level GPU time tracking. Required for GPU timeline and top-labeled metrics."))
                    toggleRow(tr("性能洞察", "Performance insights"), boolBinding(\.insightsEnabled),
                              tr("跟踪 Metal API 使用并高亮潜在性能瓶颈。", "Track Metal API usage and highlight potential bottlenecks."))
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(tr("显示选项", "Display Options"))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                VStack(spacing: 8) {
                    toggleRow(tr("显示零值指标", "Show zero-value metrics"), boolBinding(\.showZeroMetrics),
                              tr("显示值为 0 的指标。默认隐藏可能不可用的指标。", "Show metrics with value 0. Hidden by default."))
                    toggleRow(tr("显示指标范围", "Show metrics range"), boolBinding(\.showMetricsRange),
                              tr("报告最近 1200 帧的指标范围。", "Report metric range over the last 1200 frames."))
                    toggleRow(tr("禁用菜单栏 HUD 菜单", "Disable menu bar HUD menu"), boolBinding(\.disableMenuBar),
                              tr("隐藏菜单栏的 Metal HUD 菜单项。", "Hide the Metal HUD menu bar item."))
                }
            }
        }
    }

    @ViewBuilder
    private func dependencyBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .foregroundStyle(.orange)
    }

    @ViewBuilder
    private func toggleRow(_ title: String, _ binding: Binding<Bool>, _ hint: String, dependency: String? = nil) -> some View {
        HStack(spacing: 4) {
            Toggle(title, isOn: binding)
                .toggleStyle(.checkbox)
                .lineLimit(1)
            if let dependency {
                dependencyBadge(dependency)
            }
            Spacer(minLength: 0)
            InfoHint(text: hint)
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            collapsibleHeader(
                title: tr("高级", "Advanced"),
                isExpanded: advancedExpanded
            ) {
                withAnimation(.easeInOut(duration: 0.2)) { advancedExpanded.toggle() }
            }
            if advancedExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    intStepperRow(
                        title: tr("GPU 时间线帧数", "GPU timeline frame count"),
                        binding: intOptionalBinding(\.encoderGpuTimelineFrameCount, default: 6),
                        range: 1...30,
                        isSet: options.encoderGpuTimelineFrameCount != nil,
                        onClear: { clearIntOptional(\.encoderGpuTimelineFrameCount) },
                        hint: tr("GPU 时间线显示的最大帧数。默认 6。", "Max frames in GPU timeline. Default 6.")
                    )
                    intStepperRow(
                        title: tr("GPU 时间线更新间隔", "GPU timeline update interval"),
                        binding: intOptionalBinding(\.encoderGpuTimelineSwapDelta, default: 1),
                        range: 1...10,
                        isSet: options.encoderGpuTimelineSwapDelta != nil,
                        onClear: { clearIntOptional(\.encoderGpuTimelineSwapDelta) },
                        hint: tr("GPU 时间线更新间隔（秒）。默认 1。", "GPU timeline update interval in seconds. Default 1.")
                    )
                    intStepperRow(
                        title: tr("指标超时", "Metric timeout"),
                        binding: intOptionalBinding(\.metricTimeout, default: 5),
                        range: 1...60,
                        isSet: options.metricTimeout != nil,
                        onClear: { clearIntOptional(\.metricTimeout) },
                        hint: tr("瞬态指标（如 MetalFX）自动隐藏的超时（秒）。默认 5。", "Timeout for transient metrics like MetalFX. Default 5s.")
                    )
                    intStepperRow(
                        title: tr("洞察超时", "Insight timeout"),
                        binding: intOptionalBinding(\.insightTimeout, default: 10),
                        range: 1...60,
                        isSet: options.insightTimeout != nil,
                        onClear: { clearIntOptional(\.insightTimeout) },
                        hint: tr("性能洞察消失前的超时（秒）。默认 10。", "Timeout before an insight disappears. Default 10s.")
                    )
                    intStepperRow(
                        title: tr("洞察报告间隔", "Insight report interval"),
                        binding: intOptionalBinding(\.insightReportInterval, default: 5),
                        range: 1...60,
                        isSet: options.insightReportInterval != nil,
                        onClear: { clearIntOptional(\.insightReportInterval) },
                        hint: tr("性能洞察报告间隔（秒）。默认 5。", "Insight report interval in seconds. Default 5.")
                    )
                    intStepperRow(
                        title: tr("资源使用更新间隔", "Resource usage update interval"),
                        binding: intOptionalBinding(\.rusageUpdateInterval, default: 3),
                        range: 1...30,
                        isSet: options.rusageUpdateInterval != nil,
                        onClear: { clearIntOptional(\.rusageUpdateInterval) },
                        hint: tr("系统资源使用更新间隔（秒）。默认 3。", "System resource usage update interval. Default 3s.")
                    )
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(tr("性能报告路径", "Report URL"))
                                .rowTitleStyle()
                            Spacer()
                            Button(tr("选择", "Choose")) { model.chooseMetalHUDReportURL() }
                            if options.reportURL == nil {
                                Button(tr("使用默认", "Use Default")) { model.useDefaultReportURL() }
                            } else {
                                Button(tr("打开", "Open")) { model.revealReportURLInFinder() }
                                Button(tr("清除", "Clear")) { model.clearMetalHUDReportURL() }
                            }
                            InfoHint(text: tr("应用可写的路径，系统会把性能报告写入此处。默认存放在应用支持目录下。", "App-writable path where the system writes performance reports. Defaults to Application Support."))
                        }
                        if let path = options.reportURL {
                            Text(path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(.leading, 4)
                        } else {
                            Text(tr("未选择，点击「使用默认」可快速设置", "None selected. Click \"Use Default\" for quick setup"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.leading, 16)
                .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private func intStepperRow(title: String, binding: Binding<Int>, range: ClosedRange<Int>, isSet: Bool, onClear: @escaping () -> Void, hint: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .rowTitleStyle()
            Spacer()
            Stepper(value: binding, in: range) {
                Text("\(binding.wrappedValue)")
                    .monospacedDigit()
                    .foregroundStyle(isSet ? .primary : .secondary)
                    .frame(width: 32, alignment: .trailing)
            }
            if isSet {
                Button(tr("清除", "Clear")) { onClear() }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
            InfoHint(text: hint)
        }
    }

    @ViewBuilder
    private var presetsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(tr("快速预设", "Presets"))
            VStack(spacing: 8) {
                presetButton(.minimal,
                             title: tr("极简", "Minimal"),
                             description: tr("仅看运行状态：设备型号、窗口尺寸、内存占用、帧率与发热，适合日常游戏", "Just runtime status: device, layer size, memory, FPS and thermal — for everyday gaming"))
                presetButton(.balanced,
                             title: tr("均衡", "Balanced"),
                             description: tr("加入 FPS 曲线、GPU 耗时、帧间隔、游戏模式与 MetalFX 状态，适合调画质找卡顿", "Adds FPS graph, GPU time, frame interval, game mode & MetalFX — for tuning settings and spotting hitches"))
                presetButton(.complex,
                             title: tr("复杂", "Complex"),
                             description: tr("进一步呈现延迟、帧间隔直方图、CPU 时间、着色器、磁盘 IO 与编码器调用，适合深挖性能瓶颈", "Further exposes present delay, frame interval histogram, CPU time, shaders, disk IO & encoder calls — for digging into bottlenecks"))
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func collapsibleHeader(title: String, isExpanded: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(title)
                    .font(.headline)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func presetButton(_ preset: MetalHUDPreset, title: String, description: String) -> some View {
        let isSelected = model.currentMetalHUDPreset() == preset
        Button {
            model.applyMetalHUDPreset(preset)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title)
                    .font(.body.bold())
                    .foregroundStyle(isSelected ? Color.accentColor : .primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1.5)
            )
            .animation(.easeInOut(duration: 0.25), value: isSelected)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private extension View {
    func rowTitleStyle() -> some View {
        self
            .foregroundStyle(.primary)
    }
}

private struct InfoHint: View {
    let text: String
    @State private var isHovering = false
    @State private var showPopover = false
    @State private var hoverTask: Task<Void, Never>?

    private var popoverWidth: CGFloat {
        switch text.count {
        case 0...20: return 180
        case 21...40: return 240
        case 41...70: return 300
        default: return 360
        }
    }

    private var popoverFont: Font {
        switch text.count {
        case 0...30: return .callout
        default: return .caption
        }
    }

    var body: some View {
        Image(systemName: "info.circle")
            .foregroundStyle(.secondary)
            .font(.caption)
            .padding(6)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                hoverTask?.cancel()
                if hovering {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        guard !Task.isCancelled, isHovering else { return }
                        showPopover = true
                    }
                } else {
                    hoverTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled, !isHovering else { return }
                        showPopover = false
                    }
                }
            }
            .onTapGesture { showPopover.toggle() }
            .accessibilityLabel(text)
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                Text(text)
                    .font(popoverFont)
                    .padding(10)
                    .frame(width: popoverWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
    }
}

private struct ProcessSelectionView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showingFavoriteProcessEditor = false

    private var filteredProcesses: [SystemProcess] {
        guard !searchText.isEmpty else { return model.runningProcesses }
        return model.runningProcesses.filter { $0.matches(searchText: searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("手动选择进程", "Select Processes")).font(.title2.bold())
                    Text(tr("选择需要提高优先级的进程", "Choose processes whose priority should be increased"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("取消", "Cancel")) { dismiss() }
            }
            TextField(tr("搜索进程名称、目录或 PID", "Search process name, location, or PID"), text: $searchText)
                .textFieldStyle(.roundedBorder)
            if model.runningProcesses.isEmpty {
                ProgressView(tr("正在读取进程", "Loading processes"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredProcesses) { process in
                    Toggle(isOn: Binding(
                        get: { model.selectedProcessIDs.contains(process.pid) },
                        set: { selected in
                            if selected, model.selectedProcessIDs.count < 64 { model.selectedProcessIDs.insert(process.pid) }
                            else { model.selectedProcessIDs.remove(process.pid) }
                        }
                    )) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(process.displayName)
                                    .font(.headline)
                                Text("CPU \(process.cpuUsage.formatted(.number.precision(.fractionLength(1))))% · PID \(process.pid) · \(tr("目录", "Location")) · \(process.locationPath ?? process.command)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Button {
                                model.toggleFavoriteProcess(process)
                            } label: {
                                Image(systemName: model.isFavoriteProcess(process) ? "star.fill" : "star")
                                    .foregroundStyle(model.isFavoriteProcess(process) ? .yellow : .secondary)
                            }
                            .buttonStyle(.borderless)
                            .help(model.isFavoriteProcess(process) ? tr("取消收藏", "Remove favorite") : tr("收藏进程", "Favorite process"))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            HStack(spacing: 8) {
                Button(tr("常用进程优化", "Optimize Favorite Processes")) { model.increaseFavoriteProcessPriority() }
                    .disabled(model.configuration.favoriteProcessNames.isEmpty)
                Menu {
                    Button(tr("编辑常用进程", "Edit Favorite Processes")) { showingFavoriteProcessEditor = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                Text(tr("已选择 \(model.selectedProcessIDs.count)/64 个进程", "\(model.selectedProcessIDs.count)/64 process(es) selected"))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(tr("提高优先级", "Increase Priority")) { model.increaseSelectedProcessPriority() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.selectedProcessIDs.isEmpty)
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 520)
        .sheet(isPresented: $showingFavoriteProcessEditor) {
            FavoriteProcessEditorView().environmentObject(model)
        }
    }
}

private struct FavoriteProcessEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var processName = ""

    private var normalizedName: String {
        processName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tr("编辑常用进程", "Edit Favorite Processes"))
                        .font(.title2.bold())
                    Text(tr("常用进程优化只会按完整且区分大小写的进程名进行搜索", "Favorite optimization only searches complete, case-sensitive process names"))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("完成", "Done")) { dismiss() }
            }

            HStack {
                TextField(tr("输入精确进程名", "Enter exact process name"), text: $processName)
                    .textFieldStyle(.roundedBorder)
                Button(tr("添加常用进程", "Add Favorite Process")) {
                    model.addFavoriteProcess(processName)
                    processName = ""
                }
                .disabled(normalizedName.isEmpty || model.configuration.favoriteProcessNames.contains(normalizedName) || model.configuration.favoriteProcessNames.count >= ConfigurationStore.maxFavoriteProcessNames)
            }

            if model.configuration.favoriteProcessNames.isEmpty {
                Text(tr("尚未收藏常用进程", "No favorite processes saved"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(model.configuration.favoriteProcessNames, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        Button(tr("删除", "Delete"), role: .destructive) {
                            model.removeFavoriteProcess(name)
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .padding(22)
        .frame(width: 560, height: 420)
    }
}

private struct MetalHUDProcessManagerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: MetalHUDProcessCategory? = nil
    @State private var forceTermination = false

    private var filteredProcesses: [MetalHUDProcess] {
        model.interferingProcesses.filter { process in
            let matchesCategory = selectedCategory == nil || process.category == selectedCategory
            let matchesSearch = searchText.isEmpty
                || process.name.localizedCaseInsensitiveContains(searchText)
                || process.command.localizedCaseInsensitiveContains(searchText)
                || String(process.pid).contains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    private var isAllFilteredSelected: Bool {
        guard !filteredProcesses.isEmpty else { return false }
        return filteredProcesses.allSatisfy { model.selectedInterferingPIDs.contains($0.pid) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tr("Metal HUD 进程排查与关闭", "Metal HUD Process Manager"))
                            .font(.title2.bold())
                        if model.isScanningInterferingProcesses {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    Text(tr("已在运行的游戏、平台启动器（如 Steam、CrossOver）或 Wine 服务不会自动继承新的 HUD 配置。在此关闭后重新启动即可应用新样式。",
                            "Running games, launchers (Steam, CrossOver), or Wine services do not auto-refresh HUD config. Terminate them here and restart."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(tr("重新扫描", "Rescan")) { model.scanInterferingProcesses() }
                    .controlSize(.small)
                Button(tr("完成", "Done")) { dismiss() }
                    .controlSize(.small)
            }

            // Filter & Search bar
            HStack(spacing: 10) {
                TextField(tr("搜索进程名、PID 或路径", "Search process name, PID, or path"), text: $searchText)
                    .textFieldStyle(.roundedBorder)

                Picker(tr("分类", "Category"), selection: $selectedCategory) {
                    Text(tr("全部分类", "All Categories")).tag(nil as MetalHUDProcessCategory?)
                    ForEach(MetalHUDProcessCategory.allCases, id: \.self) { cat in
                        Text(tr(cat.titleZh, cat.titleEn)).tag(cat as MetalHUDProcessCategory?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
            }

            // Process List or Empty View
            if model.isScanningInterferingProcesses && model.interferingProcesses.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(tr("正在扫描可能影响 HUD 的运行中进程…", "Scanning for interfering processes…"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.interferingProcesses.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 38))
                        .foregroundStyle(.green)
                    Text(tr("未检测到可能会影响 Metal HUD 刷新的运行中进程", "No interfering processes detected"))
                        .font(.headline)
                    Text(tr("当前没有运行中的游戏启动器、Wine 服务或冲突游戏。新启动的应用将直接应用最新的 Metal HUD 样式。",
                            "No running launchers, Wine daemons, or conflicting games. Newly launched apps will apply the latest Metal HUD style."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 400)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Quick select bar
                    HStack {
                        Button(isAllFilteredSelected ? tr("取消全选", "Deselect All") : tr("全选当前", "Select All")) {
                            if isAllFilteredSelected {
                                for p in filteredProcesses { model.selectedInterferingPIDs.remove(p.pid) }
                            } else {
                                for p in filteredProcesses { model.selectedInterferingPIDs.insert(p.pid) }
                            }
                        }
                        .controlSize(.small)
                        Spacer()
                        Text(tr("共检测到 \(model.interferingProcesses.count) 个相关进程", "Found \(model.interferingProcesses.count) process(es)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 6)

                    List(filteredProcesses) { process in
                        processRow(process)
                    }
                    .listStyle(.inset)
                }
            }

            // Bottom bar
            HStack(alignment: .center, spacing: 12) {
                Toggle(tr("强制结束 (SIGKILL)", "Force terminate (SIGKILL)"), isOn: $forceTermination)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text(tr("已选 \(model.selectedInterferingPIDs.count) 个进程", "\(model.selectedInterferingPIDs.count) selected"))
                    .font(.caption)
                    .foregroundStyle(model.selectedInterferingPIDs.isEmpty ? .secondary : .primary)
                    .monospacedDigit()

                Button {
                    model.terminateSelectedInterferingProcesses(force: forceTermination)
                } label: {
                    HStack(spacing: 4) {
                        if model.isTerminatingInterferingProcesses {
                            ProgressView().controlSize(.small)
                        }
                        Text(tr("关闭所选进程", "Terminate Selected"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.selectedInterferingPIDs.isEmpty || model.isTerminatingInterferingProcesses)
            }
        }
        .padding(22)
        .frame(minWidth: 680, minHeight: 520)
    }

    @ViewBuilder
    private func processRow(_ process: MetalHUDProcess) -> some View {
        let isSelected = model.selectedInterferingPIDs.contains(process.pid)
        HStack(alignment: .center, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { isSelected },
                set: { selected in
                    if selected { model.selectedInterferingPIDs.insert(process.pid) }
                    else { model.selectedInterferingPIDs.remove(process.pid) }
                }
            ))
            .labelsHidden()
            .toggleStyle(.checkbox)

            // Icon
            processIcon(for: process)
                .frame(width: 32, height: 32)

            // Details
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(process.name)
                        .font(.headline)

                    categoryBadge(process.category)

                    Text("PID \(process.pid)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                Text(tr(process.reasonZh, process.reasonEn))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(process.command)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(tr("关闭", "Close")) {
                model.terminateSingleInterferingProcess(process, force: forceTermination)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func categoryBadge(_ category: MetalHUDProcessCategory) -> some View {
        HStack(spacing: 3) {
            Image(systemName: category.iconName)
                .font(.system(size: 9))
            Text(tr(category.titleZh, category.titleEn))
                .font(.caption2)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(categoryBadgeColor(category).opacity(0.12), in: Capsule())
        .foregroundStyle(categoryBadgeColor(category))
    }

    private func categoryBadgeColor(_ category: MetalHUDProcessCategory) -> Color {
        switch category {
        case .launcher: return .blue
        case .wineRuntime: return .orange
        case .gameOrApp: return .purple
        }
    }

    @ViewBuilder
    private func processIcon(for process: MetalHUDProcess) -> some View {
        if let path = process.appBundlePath, FileManager.default.fileExists(atPath: path) {
            let img = NSWorkspace.shared.icon(forFile: path)
            Image(nsImage: img)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: process.category.iconName)
                .font(.system(size: 20))
                .foregroundStyle(categoryBadgeColor(process.category))
        }
    }
}

private struct FeatureCard<Content: View>: View {
    @Environment(\.dashboardColorScheme) private var colorScheme
    @Environment(\.nativeGlassEnabled) private var nativeGlassEnabled
    @Environment(\.usesLiquidGlassUI) private var usesLiquidGlassUI
    let icon: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(icon: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.icon = icon; self.title = title; self.subtitle = subtitle; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon).font(.title).foregroundStyle(.purple)
            Text(title).font(.title3.bold())
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 4)
            content
                .liquidGlassButtonStyle()
        }
        .padding(18).frame(minHeight: 180)
        .liquidGlassCard(cornerRadius: 18, colorScheme: colorScheme, usesLiquidGlassUI: usesLiquidGlassUI, nativeGlassEnabled: nativeGlassEnabled)
    }
}

private struct NativeGlassEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private struct DashboardColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .light
}

private struct UsesLiquidGlassUIKey: EnvironmentKey {
    static let defaultValue = false
}

private extension EnvironmentValues {
    var nativeGlassEnabled: Bool {
        get { self[NativeGlassEnabledKey.self] }
        set { self[NativeGlassEnabledKey.self] = newValue }
    }

    var dashboardColorScheme: ColorScheme {
        get { self[DashboardColorSchemeKey.self] }
        set { self[DashboardColorSchemeKey.self] = newValue }
    }

    var usesLiquidGlassUI: Bool {
        get { self[UsesLiquidGlassUIKey.self] }
        set { self[UsesLiquidGlassUIKey.self] = newValue }
    }
}

private struct WindowAppearanceConfigurator: NSViewRepresentable {
    @Binding var nativeGlassEnabled: Bool
    let colorScheme: ColorScheme
    let isEnabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { configure(view.window, context: context) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView.window, context: context) }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func configure(_ window: NSWindow?, context: Context) {
        guard let window else { return }
        guard isEnabled else {
            window.isOpaque = true
            window.backgroundColor = .windowBackgroundColor
            window.titlebarAppearsTransparent = false
            window.animationBehavior = .default
            window.contentView?.layer?.backgroundColor = nil
            return
        }
        window.isOpaque = true
        window.backgroundColor = fallbackBackgroundColor
        window.titlebarAppearsTransparent = true
        window.animationBehavior = .none
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.backgroundColor = fallbackBackgroundColor.cgColor
        context.coordinator.configure(for: window) {
            nativeGlassEnabled = false
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
        } didRestore: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                nativeGlassEnabled = NSApp.isActive
            }
        }
    }

    private var fallbackBackgroundColor: NSColor {
        colorScheme == .dark
            ? NSColor(calibratedRed: 0.035, green: 0.045, blue: 0.07, alpha: 1.0)
            : NSColor(calibratedRed: 0.965, green: 0.97, blue: 0.995, alpha: 1.0)
    }

    @MainActor final class Coordinator: NSObject {
        private weak var observedWindow: NSWindow?
        private var willMiniaturize: (() -> Void)?
        private var didRestore: (() -> Void)?

        func configure(for window: NSWindow, willMiniaturize: @escaping () -> Void, didRestore: @escaping () -> Void) {
            self.willMiniaturize = willMiniaturize
            self.didRestore = didRestore
            guard observedWindow !== window else { return }
            if let observedWindow {
                NotificationCenter.default.removeObserver(self, name: NSWindow.willMiniaturizeNotification, object: observedWindow)
                NotificationCenter.default.removeObserver(self, name: NSWindow.didDeminiaturizeNotification, object: observedWindow)
            }
            observedWindow = window
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowWillMiniaturize),
                name: NSWindow.willMiniaturizeNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidDeminiaturize),
                name: NSWindow.didDeminiaturizeNotification,
                object: window
            )
        }

        @objc private func windowWillMiniaturize() {
            willMiniaturize?()
        }

        @objc private func windowDidDeminiaturize() {
            didRestore?()
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private extension View {
    @ViewBuilder
    func liquidGlassCard(cornerRadius: CGFloat, colorScheme: ColorScheme, usesLiquidGlassUI: Bool, nativeGlassEnabled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if !usesLiquidGlassUI {
            self
                .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.white.opacity(0.72), in: shape)
                .overlay(shape.stroke(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)))
        } else if #available(macOS 26.0, *), nativeGlassEnabled {
            self
                .background(liquidGlassFallbackFill(colorScheme), in: shape)
                .glassEffect(.clear.interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.24), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 14, y: 6)
        } else {
            self
                .background(stableGlassFill(colorScheme), in: shape)
                .overlay(shape.stroke(stableGlassStroke(colorScheme), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 14, y: 6)
        }
    }

    @ViewBuilder
    func liquidGlassPanel(cornerRadius: CGFloat, colorScheme: ColorScheme, usesLiquidGlassUI: Bool, nativeGlassEnabled: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if !usesLiquidGlassUI {
            self
                .background(.ultraThinMaterial, in: shape)
        } else if #available(macOS 26.0, *), nativeGlassEnabled {
            self
                .background(liquidGlassFallbackFill(colorScheme), in: shape)
                .glassEffect(.clear.interactive(), in: shape)
                .overlay(shape.stroke(Color.white.opacity(colorScheme == .dark ? 0.18 : 0.26), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 12, y: 5)
        } else {
            self
                .background(stableGlassFill(colorScheme), in: shape)
                .overlay(shape.stroke(stableGlassStroke(colorScheme), lineWidth: 0.7))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 12, y: 5)
        }
    }

    @ViewBuilder
    func liquidGlassButton(prominent: Bool = false) -> some View {
        self.modifier(LiquidGlassButtonModifier(prominent: prominent))
    }

    @ViewBuilder
    func liquidGlassButtonStyle() -> some View {
        self.modifier(LiquidGlassButtonModifier(prominent: false))
    }

    func liquidGlassFallbackFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.14)
    }

    func stableGlassFill(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.black.opacity(0.46) : Color.white.opacity(0.64)
    }

    func stableGlassStroke(_ colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color.white.opacity(0.16) : Color.black.opacity(0.08)
    }
}

private struct LiquidGlassButtonModifier: ViewModifier {
    @Environment(\.nativeGlassEnabled) private var nativeGlassEnabled
    @Environment(\.usesLiquidGlassUI) private var usesLiquidGlassUI
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), usesLiquidGlassUI && nativeGlassEnabled {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content
        }
    }
}
