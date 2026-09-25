import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MetalPilotCore
#endif

public struct OverviewSectionView: View {
    @EnvironmentObject private var model: AppModel
    var onNavigateToSection: ((NavigationCategory) -> Void)?

    private var isSteamDeckActive: Bool {
        model.configuration.hostnameBackup != nil
    }

    public init(onNavigateToSection: ((NavigationCategory) -> Void)? = nil) {
        self.onNavigateToSection = onNavigateToSection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Live Stats Strip
            liveStatsStrip

            // Quick Boost Cards (3x2 Grid)
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("快捷操作", "Quick Actions", "クイック操作"))
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], spacing: 16) {
                    // Frame Gen & Scaling Card
                    quickFrameGenCard

                    // Metal HUD Card
                    quickMetalHUDCard

                    // CrossOver Priority Card
                    quickCrossOverCard

                    // Disk Mounts Card
                    quickDiskCard

                    // SteamDeck Spoof Card
                    quickSteamDeckCard

                    // HoYoGames Launch Assistant Card
                    quickHoYoCard
                }
            }
        }
    }

    // MARK: - Live Stats Strip

    private var liveStatsStrip: some View {
        HStack(spacing: 12) {
            MetricStatCard(
                icon: "chart.xyaxis.line",
                title: tr("Metal HUD 状态", "Metal HUD State", "Metal HUD 状態"),
                value: model.metalHUDEnabled ? tr("已开启", "ACTIVE", "有効") : tr("未开启", "OFF", "無効"),
                subtitle: model.metalHUDEnabled ? tr("系统环境已注入", "Env Injected", "環境変数注入済み") : tr("点击下方开启", "Tap to enable", "クリックで有効化"),
                accentColor: model.metalHUDEnabled ? .green : .secondary
            )

            MetricStatCard(
                icon: "externaldrive.fill",
                title: tr("外接游戏磁盘", "Mounted Disks", "接続ディスク"),
                value: "\(model.configuration.diskPresets.count)",
                subtitle: tr("已配置的挂载预设", "Saved presets", "保存済みプリセット"),
                accentColor: .cyan
            )

            MetricStatCard(
                icon: "rectangle.2.swap",
                title: tr("主机名模式", "Hostname Mode", "ホスト名モード"),
                value: isSteamDeckActive ? "SteamDeck" : "Mac Native",
                subtitle: isSteamDeckActive ? tr("反作弊伪装中", "Spoofing active", "偽装モード中") : tr("原生主机名", "Standard macOS", "Mac標準"),
                accentColor: isSteamDeckActive ? .purple : .secondary
            )

            MetricStatCard(
                icon: "gamecontroller.fill",
                title: tr("最近启动记录", "Recent Games", "最近のゲーム"),
                value: "\(model.configuration.recentMetalHUDApps.count)",
                subtitle: tr("快速启动就绪", "Ready to launch", "起動可能"),
                accentColor: .green
            )
        }
    }

    // MARK: - Quick Action Boxes

    private var quickFrameGenCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("画质超分与补帧", "Scaling & Frame Gen", "超解像と補フレーム"), systemImage: "sparkles.tv")
                        .font(.headline)
                        .foregroundStyle(model.isScalingActive ? .purple : .primary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.isScalingActive },
                        set: { _ in model.toggleScaling() }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Text(tr("零延迟硬件补帧、MetalFX 超分与 CAS 锐化", "Zero-latency hardware FG & MetalFX upscaling.", "ゼロ遅延ハードウェア補正とMetalFX超解像。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Button(tr("进入调优", "Tune", "詳細設定")) {
                        onNavigateToSection?(.frameGen)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let currentWindowID = model.selectedWindowID,
                       let win = model.availableWindows.first(where: { $0.id == currentWindowID }) {
                        Text(win.appName)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(4)
        }
    }

    private var quickMetalHUDCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("Metal HUD 监视器", "Metal HUD Monitor", "Metal HUD モニター"), systemImage: "chart.xyaxis.line")
                        .font(.headline)
                        .foregroundStyle(model.metalHUDEnabled ? .green : .primary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { model.metalHUDEnabled },
                        set: { model.setMetalHUD($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                }

                Text(tr("实时呈现 FPS、GPU 与 CPU 开销", "Real-time FPS and hardware overlay.", "FPS・GPU・CPU負荷をリアルタイム表示。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Button(tr("详细调优", "Tune Settings", "詳細設定")) {
                        onNavigateToSection?(.metalHUD)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(tr("排查进程", "Check Processes", "競合プロセス確認")) {
                        model.openMetalHUDProcessManager()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(4)
        }
    }

    private var quickCrossOverCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("Wine 进程优先级", "Wine Priority", "Wine プロセス優先度"), systemImage: "bolt.fill")
                        .font(.headline)
                        .foregroundStyle(.cyan)
                    Spacer()
                }

                Text(tr("调度优先级 Renice -20 减少掉帧卡顿", "Renice -20 for smoother framerate.", "Renice -20で優先度を引き上げ、カクつきを軽減。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Button(tr("一键优化", "Optimize Now", "今すぐ最適化")) {
                        model.increaseCrossOverPriority()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(tr("更多设置", "Details", "詳細")) {
                        onNavigateToSection?(.gameBoost)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(4)
        }
    }

    private var quickDiskCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("外接磁盘游戏挂载", "Custom Disk Mounts", "外部ディスクマウント"), systemImage: "externaldrive.fill")
                        .font(.headline)
                        .foregroundStyle(.cyan)
                    Spacer()
                }

                Text(tr("重定向游戏至外置固态释放空间", "Mount SSDs to game directories.", "外部SSDにゲームをリダイレクトして空き容量を確保。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Button(tr("管理磁盘", "Manage Disks", "ディスク管理")) {
                        model.loadDisks()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button(tr("恢复上次挂载", "Restore", "前回のマウント復元")) {
                        model.restorePreviousMounts()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(4)
        }
    }

    private var quickSteamDeckCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("SteamDeck 模式伪装", "SteamDeck Mode", "SteamDeck 偽装モード"), systemImage: "rectangle.2.swap")
                        .font(.headline)
                        .foregroundStyle(isSteamDeckActive ? .purple : .primary)
                    Spacer()
                }

                Text(tr("将主机名伪装为 steamdeck 绕过反作弊", "Spoof hostname to bypass checks.", "ホスト名を「steamdeck」に偽装して制限を回避。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    Button(isSteamDeckActive ? tr("恢复主机名", "Restore", "ホスト名復元") : tr("开启伪装", "Enable", "偽装を有効化")) {
                        model.toggleSteamDeck()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isSteamDeckActive ? .red : .purple)
                    .controlSize(.small)

                    Button(tr("详情", "Details", "詳細")) {
                        onNavigateToSection?(.gameBoost)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(4)
        }
    }

    private var quickHoYoCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(tr("HoYoGames 启动帮助", "HoYoGames Assistant", "HoYoGames 起動補助"), systemImage: "gamecontroller.fill")
                        .font(.headline)
                        .foregroundStyle(model.isHoYoAssistantRunning ? .green : .purple)
                    Spacer()
                    if model.isHoYoAssistantRunning {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                Text(tr("临时路由 hosts 解决验证失败，启动后自动恢复", "Temporarily routes hosts to fix launch check.", "hostsを一時的に切り替えて認証エラーを回避。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 8) {
                    if model.isHoYoAssistantRunning {
                        Button(tr("取消运行", "Cancel", "キャンセル"), role: .destructive) {
                            model.cancelHoYoAssistant()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        Button(tr("开始运行", "Start", "開始")) {
                            model.startHoYoAssistant()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .controlSize(.small)
                    }

                    Button(tr("更多设置", "Settings", "設定")) {
                        onNavigateToSection?(.gameBoost)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(4)
        }
    }
}
