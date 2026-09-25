import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MetalPilotCore
#endif

public struct GameBoostSectionView: View {
    @EnvironmentObject private var model: AppModel

    private var isSteamDeckActive: Bool {
        model.configuration.hostnameBackup != nil
    }

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            GamingSectionHeader(
                icon: "bolt.fill",
                title: tr("游戏加速与启动优化", "Game Boost & Launch Assistant", "ゲーム高速化と起動最適化"),
                subtitle: tr("游戏专注防休眠、Wine 进程算力提速、反作弊主机名伪装与启动辅助", "Gaming focus booster, Wine process priority tuning, anti-cheat hostname spoofing & launch assistant", "ゲーム集中・スリープ防止、Wineプロセスの優先度最適化、アンチチート対策ホスト名偽装、起動アシスタント"),
                accentColor: .cyan
            )

            // 1. Gaming Focus & Anti-Sleep Mode Box
            gamingFocusBox

            // 2. CrossOver & Wine Priority Boost Box
            winePriorityBoostBox

            // 3. SteamDeck Hostname Spoofing Box
            steamDeckSpoofBox

            // 4. HoYoGames Launch Assistant Box
            hoYoAssistantBox

            // 5. Controller Latency & Game Mode Tips Box (Bottom)
            controllerAndGameModeBox
        }
    }

    // MARK: - Gaming Focus & Anti-Sleep Box

    private var gamingFocusBox: some View {
        GroupBox(label:
            HStack(spacing: 8) {
                Label(tr("游戏专注模式 (防休眠 / 防降频)", "Gaming Focus & Anti-Sleep", "ゲーム集中モード（スリープ・性能低下防止）"), systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                LiveStatusBadge(
                    model.isGamingFocusActive ? .active : .idle,
                    title: model.isGamingFocusActive ? tr("专注中 (已阻止休眠)", "Active (Sleep Blocked)", "集中モード中（スリープ抑止）") : tr("未开启", "Inactive", "未有効化")
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("运行原生 caffeinate 守护进程，在游戏、挂机或编译着色器期间阻止 macOS 自动熄屏、空闲降频和系统休眠，保障最高性能持续输出。",
                        "Runs native caffeinate daemon to prevent display dimming, CPU power throttling, and system sleep during gaming or shader compilation.",
                        "macOSネイティブのcaffeinateデーモンを実行し、ゲームプレイやシェーダーコンパイル中の画面消灯・CPU省電力スロットリング・スリープを防止して持続的な高パフォーマンスを維持します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 12) {
                    Button {
                        model.toggleGamingFocus()
                    } label: {
                        Label(
                            model.isGamingFocusActive ? tr("退出游戏专注模式", "Stop Gaming Focus", "集中モードを終了") : tr("开启游戏专注模式", "Start Gaming Focus Mode", "ゲーム集中モードを開始"),
                            systemImage: model.isGamingFocusActive ? "pause.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isGamingFocusActive ? .red : .orange)
                    .controlSize(.regular)

                    Spacer()
                }
            }
            .padding(6)
        }
    }

    // MARK: - CrossOver & Wine Priority Boost Box

    private var winePriorityBoostBox: some View {
        GroupBox(label: Label(tr("提高 CrossOver 与 Wine 进程优先级", "Increase CrossOver & Wine Priority", "CrossOver / Wine プロセスの優先度向上"), systemImage: "bolt.badge.clock.fill").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("将 Wine / GPTK 及其子游戏进程调度优先级提升至最高（Renice -20），使 CPU 核心优先分配算力给游戏主线程，显著改善卡顿与掉帧现象。",
                        "Elevate scheduling priority for Wine/GPTK game processes to maximum (Renice -20) to smooth framerates.",
                        "Wine/GPTKおよびゲームプロセスのスケジューリング優先度を最高（Renice -20）に引き上げ、ゲームのメインスレッドにCPUリソースを最優先で割り当ててスタッターやフレーム落ちを改善します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 12) {
                    Button {
                        model.increaseCrossOverPriority()
                    } label: {
                        Label(tr("自动检测并优化 (Renice -20)", "Auto Detect & Optimize", "自動検出して最適化 (Renice -20)"), systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Button {
                        model.loadProcessesForManualSelection()
                    } label: {
                        Label(tr("手动选择进程", "Manual Selection", "プロセスを手動選択"), systemImage: "list.bullet")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                    Spacer()
                }
            }
            .padding(6)
        }
    }

    // MARK: - SteamDeck Spoofing Box

    private var steamDeckSpoofBox: some View {
        GroupBox(label:
            HStack(spacing: 8) {
                Label(tr("切换到 SteamDeck 主机名模式", "SteamDeck Mode Spoofing", "SteamDeck ホスト名偽装モード"), systemImage: "rectangle.2.swap")
                    .font(.headline)
                LiveStatusBadge(
                    isSteamDeckActive ? .active : .idle,
                    title: isSteamDeckActive ? tr("已伪装为 SteamDeck", "Spoofed as SteamDeck", "SteamDeckに偽装中") : tr("原生 Mac 主机名", "Native Mac Hostname", "Mac標準ホスト名")
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("部分游戏的反作弊系统对 SteamDeck 开放后门，将 Mac 主机名临时伪装为 steamdeck 可绕过限制直接进入游戏。",
                        "Some anti-cheat systems whitelist SteamDeck. Temporarily spoofing macOS hostname to 'steamdeck' allows games to run.",
                        "一部のゲームのアンチチートはSteamDeck向けに制限を緩和しています。Macのホスト名を一時的に「steamdeck」に偽装することで互換性を向上させます。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack {
                    Button {
                        model.toggleSteamDeck()
                    } label: {
                        Label(
                            isSteamDeckActive ? tr("恢复为原始主机名", "Restore Original Hostname", "元のホスト名に復元") : tr("一键开启 SteamDeck 伪装", "Enable SteamDeck Spoofing", "SteamDeck偽装を有効化"),
                            systemImage: isSteamDeckActive ? "arrow.counterclockwise" : "shield.lefthalf.filled"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isSteamDeckActive ? .red : .purple)
                    .controlSize(.regular)

                    Spacer()

                    if let backup = model.configuration.hostnameBackup {
                        Text(tr("原始名称：\(backup.computerName)", "Original: \(backup.computerName)", "元の名前：\(backup.computerName)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: - HoYoGames Launch Assistant Box

    private var hoYoAssistantBox: some View {
        GroupBox(label:
            HStack(spacing: 8) {
                Label(tr("HoYoGames 启动辅助", "HoYoGames Launch Assistant", "HoYoGames 起動アシスタント"), systemImage: "gamecontroller.fill")
                    .font(.headline)
                LiveStatusBadge(
                    model.isHoYoAssistantRunning ? .warning : .idle,
                    title: model.isHoYoAssistantRunning ? tr("辅助中", "Active", "実行中") : tr("就绪", "Ready", "待機中")
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("点击“开始运行”后在倒计时内打开游戏，MetalPilot 将临时代理域名并在启动后自动恢复 hosts 文件，避免全局网络受影响。",
                        "Click Start, then open the game within the countdown. Hosts are automatically restored afterwards.",
                        "「実行開始」をクリック後、カウントダウン時間内にゲームを起動してください。一時的にhostsを切り替えて認証を補助し、起動後に自動で元のhostsを復元します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 14) {
                    if model.isHoYoAssistantRunning {
                        Button(role: .destructive) {
                            model.cancelHoYoAssistant()
                        } label: {
                            Label(tr("取消并立即恢复 hosts", "Cancel & Restore Hosts", "キャンセルしてhostsを復元"), systemImage: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.regular)
                    } else {
                        Button {
                            model.startHoYoAssistant()
                        } label: {
                            Label(tr("开始运行", "Start Assistant", "実行開始"), systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }

                    // Separated Label and Segmented Picker to prevent label squishing/wrapping bug
                    HStack(spacing: 8) {
                        Text(tr("等待：", "Wait:", "待機時間："))
                            .font(.subheadline)
                            .fixedSize()

                        Picker("", selection: Binding(
                            get: { model.configuration.hoYoWaitSeconds },
                            set: { model.setHoYoWaitSeconds($0) }
                        )) {
                            Text(tr("10 秒", "10s", "10秒")).tag(10)
                            Text(tr("15 秒", "15s", "15秒")).tag(15)
                            Text(tr("20 秒", "20s", "20秒")).tag(20)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                        .disabled(model.isHoYoAssistantRunning)
                    }

                    Toggle(isOn: Binding(
                        get: { model.configuration.doesNotRaiseHoYoPriority },
                        set: { model.setDoesNotRaiseHoYoPriority($0) }
                    )) {
                        Text(tr("不提升优先级", "Do not raise priority", "優先度を変更しない"))
                            .font(.subheadline)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(model.isHoYoAssistantRunning)
                    .help(tr("仅切换 hosts，倒计时结束后仍会恢复正常，但不调整 Wine 进程优先级。",
                             "Only switches hosts; hosts are still restored after the countdown, but Wine process priority is left untouched.",
                             "hostsのみ切り替えます。カウントダウン後もhostsは復元しますが、Wineプロセスの優先度は変更しません。"))

                    Spacer()
                }
            }
            .padding(6)
        }
    }

    // MARK: - Controller Latency & Game Mode Tips Box

    private var controllerAndGameModeBox: some View {
        GroupBox(label: Label(tr("手柄蓝牙低延迟与着色器科普", "Controller Latency & Shader Optimization", "コントローラーBluetooth低遅延化・シェーダー解説"), systemImage: "bookmark.fill").font(.headline)) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.blue)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("macOS 游戏模式 (Game Mode) 极速唤醒", "macOS Game Mode Low-Latency Trigger", "macOS ゲームモードによる低遅延化"))
                            .font(.caption.bold())
                        Text(tr("系统“游戏模式”会将 PS5/Xbox 蓝牙手柄与 AirPods 的采样轮询率翻倍，大幅降低无线输入与音频延迟。建议在游戏内开启“全屏独占模式 (Full Screen)”以确保稳定触发 Game Mode。",
                                "macOS Game Mode doubles Bluetooth polling rates for gamepads and AirPods, halving wireless latency. Use Full Screen mode in-game for automatic activation.",
                                "macOSの「ゲームモード」は、PS5/XboxコントローラーやAirPodsのBluetoothサンプリングレートを2倍に引き上げ、入力・音声遅延を大幅に削減します。安定して起動させるため、ゲーム内設定で「フルスクリーン表示」を選択することを推奨します。"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cpu.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("着色器动态编译卡顿 (Shader Stutter) 提示", "Shader Compilation Stutter Notice", "シェーダー動的コンパイルに関するヒント"))
                            .font(.caption.bold())
                        Text(tr("首次进入新游戏场景时，GPTK 正在后台将 DirectX 着色器动态编译并缓存在 Metal 中，可能出现短暂掉帧，属于正常转译机制。持续游玩 5~10 分钟着色器缓存建立后，游戏帧率将趋于平稳丝滑。",
                                "Entering new scenes triggers DirectX-to-Metal shader compilation. Temporary frame drops are normal and will smooth out after 5-10 minutes of caching.",
                                "新しいシーンに初めて入る際、GPTKがバックグラウンドでDirectXシェーダーをMetal用にコンパイルしてキャッシュするため、一時的なカクつきが生じることがあります。5〜10分プレイしてキャッシュが蓄積されるとフレームレートは滑らかになります。"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
        }
    }
}
