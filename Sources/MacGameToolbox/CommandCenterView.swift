import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

public struct CommandCenterView: View {
    @EnvironmentObject private var model: AppModel
    @State private var expandedTuner = false

    private var isSteamDeckActive: Bool {
        model.configuration.hostnameBackup != nil
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Top Hero Status Header
                heroStatusHeader

                // Main Modular Card Stream
                VStack(spacing: 16) {
                    // Metal HUD Suite
                    metalHUDSuiteCard

                    // Game Boost & Launch Suite
                    gameBoostSuiteCard

                    // Storage & Maintenance Suite
                    storageSuiteCard

                    // System Tools & Visuals Suite
                    systemToolsSuiteCard
                }
            }
            .padding(24)
        }
    }

    // MARK: - Hero Status Header

    private var heroStatusHeader: some View {
        HStack(spacing: 12) {
            MetricStatCard(
                icon: "chart.xyaxis.line",
                title: tr("Metal HUD 状态", "Metal HUD"),
                value: model.metalHUDEnabled ? tr("运行中", "ACTIVE") : tr("未开启", "OFF"),
                subtitle: model.metalHUDEnabled ? tr("环境已注入", "Env Injected") : tr("点击开启", "Tap to enable"),
                accentColor: model.metalHUDEnabled ? .green : .secondary
            )

            MetricStatCard(
                icon: "bolt.fill",
                title: tr("游戏加速模式", "Game Boost"),
                value: tr("已就绪", "READY"),
                subtitle: tr("Wine 优先级", "Wine priority"),
                accentColor: .cyan
            )

            MetricStatCard(
                icon: "externaldrive.fill",
                title: tr("外接游戏磁盘", "Disk Mounts"),
                value: "\(model.configuration.diskPresets.count)",
                subtitle: tr("已配置预设", "Active presets"),
                accentColor: .cyan
            )

            MetricStatCard(
                icon: "rectangle.2.swap",
                title: tr("SteamDeck 伪装", "SteamDeck Mode"),
                value: isSteamDeckActive ? tr("已开启", "ACTIVE") : tr("原生模式", "NATIVE"),
                subtitle: isSteamDeckActive ? "steamdeck" : tr("标准主机名", "Mac hostname"),
                accentColor: isSteamDeckActive ? .purple : .secondary
            )
        }
    }

    // MARK: - Metal HUD Suite Card

    private var metalHUDSuiteCard: some View {
        GroupBox(label:
            HStack(spacing: 8) {
                Label(tr("Metal HUD 性能监视器", "Metal HUD Performance Suite"), systemImage: "chart.xyaxis.line")
                    .font(.headline)
                LiveStatusBadge(model.metalHUDEnabled ? .active : .idle)
                Spacer()
                Toggle("", isOn: Binding(
                    get: { model.metalHUDEnabled },
                    set: { model.setMetalHUD($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("全局/单应用帧率与硬件开销监控，支持预设切换与参数调优", "Global & per-app HUD overlay with real-time tuning and process management."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 10) {
                    Button {
                        model.launchAppWithMetalHUD()
                    } label: {
                        Label(tr("单 App 注入启动", "Launch with HUD"), systemImage: "plus.app.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button {
                        model.openMetalHUDProcessManager()
                    } label: {
                        Label(tr("排查冲突进程", "Process Manager"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button {
                        model.openIOSHUDLauncher()
                    } label: {
                        Label(tr("iOS 设备启动", "Launch on iOS"), systemImage: "iphone.gen3")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            expandedTuner.toggle()
                        }
                    } label: {
                        Label(
                            expandedTuner ? tr("收起调节器", "Hide Tuner") : tr("展开实时调节器", "Tuner Controls"),
                            systemImage: expandedTuner ? "chevron.up" : "slider.horizontal.3"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Spacer()
                }

                if expandedTuner {
                    VStack(alignment: .leading, spacing: 12) {
                        Divider()

                        HStack(spacing: 8) {
                            Text(tr("快捷预设：", "Presets:"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            presetChip(tr("精简", "Minimal"), .minimal)
                            presetChip(tr("均衡", "Balanced"), .balanced)
                            presetChip(tr("完整", "Complex"), .complex)

                            Spacer()

                            Button(tr("重置默认", "Reset"), role: .destructive) {
                                model.resetMetalHUDOptions()
                            }
                            .controlSize(.small)
                            .buttonStyle(.borderless)
                        }

                        HStack(spacing: 20) {
                            HStack(spacing: 10) {
                                Text(tr("缩放", "Scale"))
                                    .font(.caption.bold())
                                Slider(
                                    value: Binding(
                                        get: { model.configuration.metalHUDOptions.scale },
                                        set: { var opts = model.configuration.metalHUDOptions; opts.scale = $0; model.updateMetalHUDOptions(opts) }
                                    ),
                                    in: 0.1...1.0,
                                    step: 0.05
                                )
                                Text(String(format: "%.0f%%", model.configuration.metalHUDOptions.scale * 100))
                                    .font(.caption.monospaced())
                                    .frame(width: 40)
                            }

                            HStack(spacing: 10) {
                                Text(tr("不透明度", "Opacity"))
                                    .font(.caption.bold())
                                Slider(
                                    value: Binding(
                                        get: { model.configuration.metalHUDOptions.opacity },
                                        set: { var opts = model.configuration.metalHUDOptions; opts.opacity = $0; model.updateMetalHUDOptions(opts) }
                                    ),
                                    in: 0.0...1.0,
                                    step: 0.05
                                )
                                Text(String(format: "%.0f%%", model.configuration.metalHUDOptions.opacity * 100))
                                    .font(.caption.monospaced())
                                    .frame(width: 40)
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
            .padding(6)
        }
    }

    private func presetChip(_ title: String, _ preset: MetalHUDPreset) -> some View {
        let isSelected = model.currentMetalHUDPreset() == preset
        return Button(title) {
            model.applyMetalHUDPreset(preset)
        }
        .controlSize(.small)
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : nil)
    }

    // MARK: - Game Boost Suite Card

    private var gameBoostSuiteCard: some View {
        HStack(spacing: 16) {
            GroupBox(label: Label(tr("提高 CrossOver 优先级", "CrossOver Priority"), systemImage: "bolt.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("将 Wine 游戏进程优先级提至最高（Renice -20）改善掉帧", "Elevate process priority for Wine/GPTK games."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        Button(tr("检测并优化", "Optimize")) {
                            model.increaseCrossOverPriority()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(tr("手动选择", "Select")) {
                            model.loadProcessesForManualSelection()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(4)
            }

            GroupBox(label:
                HStack(spacing: 8) {
                    Label(tr("HoYoGames 启动帮助", "HoYo Launch Assistant"), systemImage: "gamecontroller.fill")
                        .font(.headline)
                    if model.isHoYoAssistantRunning {
                        LiveStatusBadge(.warning, title: tr("运行中", "Active"))
                    }
                }
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("临时代理校验域名，启动后自动恢复 hosts", "Temporarily routes validation hosts on Mac."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        if model.isHoYoAssistantRunning {
                            Button(tr("取消恢复", "Cancel"), role: .destructive) {
                                model.cancelHoYoAssistant()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            .controlSize(.small)
                        } else {
                            Button(tr("开始运行", "Start")) {
                                model.startHoYoAssistant()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.purple)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    // MARK: - Storage Suite Card

    private var storageSuiteCard: some View {
        HStack(spacing: 16) {
            GroupBox(label: Label(tr("外接磁盘游戏挂载", "Custom Disk Mounts"), systemImage: "externaldrive.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("自定义外接 SSD 挂载点，将游戏重定向至外置存储释放空间", "Mount external SSDs to custom game directories."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        Button(tr("管理磁盘", "Manage Disks")) {
                            model.loadDisks()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(tr("恢复上次挂载", "Restore")) {
                            model.restorePreviousMounts()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(4)
            }

            GroupBox(label: Label(tr("缓存与日志清理", "Cache & Log Purge"), systemImage: "trash.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("安全扫描并清理冗余的用户缓存和系统日志", "Safely clear redundant user caches and logs."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        Button(tr("一键清理", "Clean Now"), role: .destructive) {
                            model.prepareCacheScan()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)

                        Toggle(tr("排除敏感文件", "Safe Mode"), isOn: Binding(
                            get: { model.configuration.excludesSensitiveCacheFiles },
                            set: { model.setExcludesSensitiveCacheFiles($0) }
                        ))
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    }
                }
                .padding(4)
            }
        }
    }

    // MARK: - System Tools Suite Card

    private var systemToolsSuiteCard: some View {
        HStack(spacing: 16) {
            GroupBox(label: Label(tr("SteamDeck 模式伪装", "SteamDeck Mode"), systemImage: "rectangle.2.swap").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("将主机名伪装为 steamdeck 绕过部分反作弊限制", "Spoof hostname as steamdeck to bypass anti-cheat."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button(isSteamDeckActive ? tr("恢复原生主机名", "Restore") : tr("开启 SteamDeck 伪装", "Enable Spoofing")) {
                        model.toggleSteamDeck()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isSteamDeckActive ? .red : .purple)
                    .controlSize(.small)
                }
                .padding(4)
            }

            GroupBox(label: Label(tr("教程与指南", "Guides & Tutorials"), systemImage: "book.pages.fill").font(.headline)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(tr("浏览 Mac 游戏运行、Wine 容器与 GPTK 教程", "Browse guides for Mac gaming, Wine bottles, and GPTK."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    HStack(spacing: 8) {
                        Button(tr("教程总导航", "Tutorials")) {
                            model.showingTutorials = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(4)
            }
        }
    }
}
