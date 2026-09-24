import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

public struct AboutSectionView: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            GamingSectionHeader(
                icon: "info.circle.fill",
                title: tr("关于与致谢", "About & Acknowledgements", "情報と謝辞"),
                subtitle: tr("软件版本信息、原项目引用与开源致谢", "App version, upstream repository references, and acknowledgements", "バージョン情報、オリジナルプロジェクトへの参照、謝辞"),
                accentColor: .blue
            )

            // App Identity Hero Card
            appHeroBox

            // Upstream Acknowledgements Box
            upstreamAcknowledgementBox

            // Fork Edition Improvements Box
            forkImprovementsBox

            // License & Legal Disclaimer Box
            licenseAndDisclaimerBox
        }
    }

    // MARK: - App Hero Box

    private var appHeroBox: some View {
        GroupBox {
            HStack(spacing: 20) {
                Image("MetalPilotLogo")
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.blue.opacity(0.28), radius: 8, x: 0, y: 4)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(tr("MetalPilot", "MetalPilot", "MetalPilot"))
                            .font(.title2.bold())
                        Text(AppVersion.displayString)
                            .font(.subheadline.monospaced())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }

                    Text(tr("面向 Apple Silicon 的原生游戏控制中心，专注游戏环境调优与 Metal 性能覆盖", "A native game control center for Apple Silicon, focused on gaming environment tuning and Metal performance overlays.", "Apple Silicon 向けのネイティブゲームコントロールセンター。ゲーム環境の最適化と Metal パフォーマンスオーバーレイに特化。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Text("Architecture:")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("Apple Silicon (ARM64)")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                    }
                    .padding(.top, 2)
                }

                Spacer()
            }
            .padding(10)
        }
    }

    // MARK: - Upstream Acknowledgements Box

    private var upstreamAcknowledgementBox: some View {
        GroupBox(label: Label(tr("原项目引用与特别致谢", "Original Project & Acknowledgements", "オリジナルプロジェクト・謝辞"), systemImage: "heart.fill").font(.headline).foregroundStyle(.pink)) {
            VStack(alignment: .leading, spacing: 14) {
                Text(tr("本项目由衷感谢原作者及开源社区贡献者的卓越设计与开源分享！",
                        "Special thanks to the original author and open source contributors for this fantastic Mac gaming utility!",
                        "本プロジェクトの基盤を作成された原作者およびオープンソースコミュニティの貢献者の皆様に深く感謝いたします。"))
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Text(tr("原项目作者：", "Original Author:", "オリジナル作者："))
                            .font(.caption.bold())
                            .frame(width: 120, alignment: .leading)
                        Text("我是艾文喵")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text(tr("原项目开源库：", "Upstream Repo:", "元リポジトリ："))
                            .font(.caption.bold())
                            .frame(width: 120, alignment: .leading)
                        Link("aiwentongxue/mac-gaming-toolbox", destination: URL(string: "https://github.com/aiwentongxue/mac-gaming-toolbox")!)
                            .font(.caption)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text(tr("原作者主页：", "Author Channels:", "作者チャンネル："))
                            .font(.caption.bold())
                            .frame(width: 120, alignment: .leading)
                        HStack(spacing: 12) {
                            Link("哔哩哔哩 (@我是艾文喵)", destination: URL(string: "https://b23.tv/dV7YBJQ")!)
                            Text("·").foregroundStyle(.secondary)
                            Link("YouTube Channel", destination: URL(string: "https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ")!)
                        }
                        .font(.caption)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text(tr("官方视频教程：", "Video Guides:", "動画ガイド："))
                            .font(.caption.bold())
                            .frame(width: 120, alignment: .leading)
                        HStack(spacing: 12) {
                            Link(tr("B站重磅发布教程", "Bilibili Release Video", "Bilibili 動画解説"), destination: URL(string: "https://b23.tv/qnJBcbk")!)
                            Text("·").foregroundStyle(.secondary)
                            Link(tr("YouTube 视频教程", "YouTube Video Guide", "YouTube 動画ガイド"), destination: URL(string: "https://youtu.be/Y9g4F0_6ipI?si=i3G9dxiXMbk2NSzY")!)
                        }
                        .font(.caption)
                        Spacer()
                    }

                    HStack(spacing: 12) {
                        Text(tr("生态致谢项目：", "Special Thanks:", "特別謝辞："))
                            .font(.caption.bold())
                            .frame(width: 120, alignment: .leading)
                        HStack(spacing: 12) {
                            Text("MetalGoose (Zero-latency FG & Shaders)")
                            Text("·").foregroundStyle(.secondary)
                            Text("MetalDuck (Lossless Scaling & DRS)")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(8)
        }
    }

    // MARK: - Fork Edition Improvements Box

    private var forkImprovementsBox: some View {
        GroupBox(label: Label(tr("本分支版本增强与改进", "Fork Enhancements", "本フォーク版の強化・改善機能"), systemImage: "sparkles").font(.headline)) {
            VStack(alignment: .leading, spacing: 10) {
                featureBullet(
                    title: tr("画质超分与零延迟动态补帧 (融合 MetalGoose & MetalDuck)", "Resolution Scaling & Frame Generation", "超解像スケーリングと動的補フレーム"),
                    desc: tr("基于媒体引擎与 Apple Silicon 硬件加速，实现零延迟运动外推 (2x-4x 补帧)、MetalFX 空间超分辨率、CAS 锐化、SMAA 抗锯齿与 6-Sigma EMA 场景剪辑保护。",
                             "Hardware-accelerated zero-latency motion extrapolation (2x-4x FG), MetalFX spatial upscaling, CAS sharpening, SMAA, and 6-Sigma scene-cut protection.",
                             "Media EngineとApple Siliconを活用したゼロ遅延運動外挿（2x〜4x補正）、MetalFX超解像、CAS鮮鋭化、SMAA、6-Sigmaシーンチェンジ保護。")
                )
                featureBullet(
                    title: tr("全套自定义 Metal HUD 调优、单 App 方案与性能快照", "Custom Metal HUD Tuning & Performance Snapshots", "Metal HUD 完全カスタマイズ・個別プロファイル・スナップショット"),
                    desc: tr("支持 10%~100% 缩放、0~100% 透明度、四角方位、23 项指标带单位示例、单游戏专属 HUD 方案绑定与一键导出 Markdown 性能诊断快照报告。",
                             "Full control over scale, opacity, positions, 23 metrics with unit examples, per-app profiles, and 1-click Markdown performance snapshot export.",
                             "10%〜100%のスケール調整、透明度、四隅の配置、23項目の表示項目、ゲーム別の個別プロファイル保存、Markdown形式の性能診断レポート出力をサポート。")
                )
                featureBullet(
                    title: tr("Windows 游戏存档扫描与一键 Zip 备份 (Game Save Finder)", "Windows Save Game Finder & Backup", "Windows ゲームセーブデータスキャン・Zipバックアップ"),
                    desc: tr("智能探测 CrossOver、Whisky 及 Wine 容器中的深层游戏存档目录（AppData、Saved Games、My Games），支持一键定位与打包备份。",
                             "Automatically scans and backs up Windows game save directories inside CrossOver and Whisky bottles to standard zip archives.",
                             "CrossOver、Whisky、Wineコンテナ内の深いセーブデータ階層（AppData、Saved Games、My Games）を自動検出し、一発でFinder表示・Zip保存。")
                )
                featureBullet(
                    title: tr("Caffeinate 原生游戏专注模式与手柄低延迟优化", "Gaming Focus Anti-Sleep & Low-Latency Controller", "Caffeinate ゲーム集中モード・コントローラー低遅延化"),
                    desc: tr("一键开启 caffeinate 守护进程阻止系统休眠与息屏，结合 macOS 游戏模式双倍蓝牙轮询率大幅降低手柄操作延迟。",
                             "Prevents system sleep and dimming via native caffeinate, maximizing macOS Game Mode controller sampling rates.",
                             "caffeinateデーモンによるスリープ・画面消灯の抑止と、macOSゲームモードのBluetooth高頻度サンプリングを活用した低遅延化。")
                )
                featureBullet(
                    title: tr("Metal HUD 冲突进程排查与安全重启", "Interfering Process Detection & Manager", "Metal HUD 競合プロセスの診断と安全な再起動"),
                    desc: tr("智能识别先于 HUD 启动的 Steam、CrossOver、Whisky、Wine 容器进程，提供用户自主勾选并安全重启服务，彻底解决 HUD 不显示问题。",
                             "Intelligently identifies conflicting launchers and Wine daemons running prior to HUD injection for user-selected safe restarts.",
                             "HUD有効化前に起動していたランチャーやWineプロセスを自動検出し、チェックを入れて安全に再起動することで非表示問題を解決。")
                )
                featureBullet(
                    title: tr("多语言动态切换 (中 / 英 / 日) 与纯原生 ARM64 构建", "Multi-Language (ZH/EN/JA) & Pure ARM64 Build", "多言語対応（日本語・英語・簡体中文）とネイティブARM64ビルド"),
                    desc: tr("支持系统跟随及应用内三语自由切换，基于 NavigationSplitView 重构，专为 Apple Silicon 芯片纯原生编译分发。",
                             "Supports System/Chinese/English/Japanese switching, fully redesigned for Apple Silicon native performance.",
                             "システム言語自動追従およびアプリ内での3言語切り替えに対応。Apple Silicon向けに最適化された高速・軽量ネイティブ設計。")
                )
            }
            .padding(6)
        }
    }

    private func featureBullet(title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.bold())
                Text(desc)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - License & Legal Disclaimer Box

    private var licenseAndDisclaimerBox: some View {
        GroupBox(label: Label(tr("开源许可与免责声明", "License & Disclaimer", "ライセンス・免責事項"), systemImage: "doc.text.fill").font(.headline)) {
            VStack(alignment: .leading, spacing: 8) {
                Text(tr("开源许可证：GNU General Public License v3.0 (GPL-3.0)", "License: GNU General Public License v3.0 (GPL-3.0)", "ライセンス：GNU General Public License v3.0 (GPL-3.0)"))
                    .font(.caption.bold())
                Text(tr("本项目为开源辅助工具，并非 Apple、CodeWeavers、HoYoverse 或 Valve 的官方产品。文中出现的所有商标及名称均归其各自所有者拥有。",
                        "This project is an open-source utility and is not affiliated with Apple, CodeWeavers, HoYoverse, or Valve. All trademarks belong to their respective owners.",
                        "本プロジェクトはオープンソースの補助ユーティリティであり、Apple、CodeWeavers、HoYoverse、Valveの公式製品ではありません。記載されている商標はそれぞれの所有者に帰属します。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(6)
        }
    }
}
