import SwiftUI

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("4.3.0") {
                    Text(tr("【辅助服务品牌迁移】特权辅助服务标识由 macgametoolbox.helper 迁移为 metalpilot.helper，系统后台活动与登录项显示新名称，旧服务与历史残留将自动清理",
                            "Privileged helper identity migrated from macgametoolbox.helper to metalpilot.helper; legacy daemons are cleaned up automatically",
                            "【ヘルパー移行】特権ヘルパー識別子を macgametoolbox.helper から metalpilot.helper へ移行し、旧デーモンを自動クリーンアップ"))
                    Text(tr("【迁移完全可选】检测到旧版辅助服务时可选择立即迁移或保留共存，共存模式下新旧两个应用互不影响，可随时在系统页迁移",
                            "Helper migration is now fully optional: migrate or keep the legacy service for side-by-side use, switchable anytime from the System page",
                            "【移行完全任意】旧ヘルパー検出時に移行または共存を選択可能。システムページからいつでも切り替えられます"))
                }
                Section("4.0.0") {
                    Text(tr("【画质超分与补帧】融合 MetalGoose 与 MetalDuck 优势，打造 macOS 专属无损画质与动态插帧引擎",
                            "Integrated super resolution and zero-latency frame generation engine combining MetalGoose & MetalDuck",
                            "【超解像と補フレーム】MetalGooseとMetalDuckの長所を統合し、macOS専用の動的補フレームエンジンを新搭載"))
                    Text(tr("【零延迟硬件外推】利用 Apple Silicon 媒体引擎 (Media Engine) 硬件加速与 Metal 计算着色器，实现 0 ms 额外输入延迟的 2x/3x/4x 补帧",
                            "Hardware motion extrapolation (2x/3x/4x FG) on Media Engine with 0 ms added latency",
                            "【ゼロ遅延ハードウェア外挿】Media Engineを活用した0ms追加遅延の2x/3x/4x補フレーム"))
                    Text(tr("【MetalFX 空间超分辨率】支持 33%、50%、67%、75% 及原生缩放，以更低 GPU 渲染成本输出高清画面",
                            "MetalFX spatial upscaling supporting 33%, 50%, 67%, 75% render scales",
                            "【MetalFX超解像】33%〜75%のレンダリング解像度から高精細にアップスケール"))
                    Text(tr("【后处理画质管线】内置 CAS 对比度自适应锐化与 FXAA / SMAA / TAA (时域重投影抗锯齿) 完整抗锯齿方案",
                            "Full post-processing pipeline with CAS sharpening, FXAA, SMAA, and TAA",
                            "【画質処理パイプライン】CAS鮮鋭化、FXAA、SMAA、TAA（テンポラルアンチエイリアス）を完備"))
                    Text(tr("【自适应场景保护】64x64 亮度网格与 6-Sigma EMA 场景剪辑检测，镜头切换瞬间回退直通，杜绝形变撕裂",
                            "Adaptive 6-Sigma EMA scene-cut protection preventing morphing on camera cuts",
                            "【シーンチェンジ保護】6-Sigma EMAによる適応型シーンチェンジ検出で歪み・ティアリングを防止"))
                    Text(tr("【高刷合成光标与快捷键】全局快捷键 ⌘⇧T 开关、⌘⇧C 光标约束锁定与高刷硬件合成光标",
                            "Global shortcuts (⌘⇧T / ⌘⇧C), mouse constraint lock, and synthetic cursor",
                            "【合成カーソルとショートカット】⌘⇧T / ⌘⇧C グローバルショートカットとハードウェア合成カーソル"))
                }
                Section("3.1.0") {
                    Text(tr("【UI 重构】全面采用 macOS 原生 NavigationSplitView 侧边栏架构与标准控件，告别多层嵌套弹窗",
                            "Refactored UI to pure native NavigationSplitView sidebar and standard controls",
                            "【UI刷新】macOS標準のNavigationSplitViewサイドバー構成と標準コントロールを採用し、階層ダイアログを撤廃"))
                    Text(tr("【Metal HUD 进阶】支持 10%~100% 缩放、透明度、四角方位、23 项指标（带数值单位）与单应用专属方案绑定",
                            "Added custom scale, opacity, alignment, 23 metrics with unit examples, and per-app HUD profiles",
                            "【Metal HUD進化】10%〜100%スケール、透明度、四隅配置、23項目の表示指標、アプリ個別プロファイルに対応"))
                    Text(tr("【性能诊断快照】支持一键生成结构化 Markdown 性能诊断报告，方便社区反馈与硬件评估",
                            "Added 1-click Markdown performance diagnostic snapshot report exporter",
                            "【性能診断スナップショット】ワンクリックでMarkdown形式の性能診断レポートを出力可能に"))
                    Text(tr("【进程排查与重启】智能排查先于 HUD 启动的冲突进程（Steam、CrossOver、Wine），支持用户自主勾选安全重启",
                            "Added interfering process inspector with user-selected safe restarts for reliable HUD injection",
                            "【競合プロセス診断】HUD起動前に常駐していたSteam/CrossOver/Wineプロセスを検出し、安全に再起動"))
                    Text(tr("【存档管理】自动扫描 CrossOver、Whisky、Wine 容器深层存档（AppData、Saved Games），支持一键定位与 Zip 备份",
                            "Added Windows Game Save Finder & 1-click Zip backup for CrossOver and Whisky bottles",
                            "【セーブデータ管理】Wine/CrossOver/Whiskyボトルの深層セーブデータを自動スキャンし、Finder表示・Zip保存"))
                    Text(tr("【游戏专注模式】内置原生 Caffeinate 守护进程，游戏与着色器编译期间全程防休眠、防息屏与防降频",
                            "Added Caffeinate Gaming Focus Mode to prevent sleep, screen dimming, and throttling",
                            "【ゲーム集中モード】Caffeinateデーモンにより、ゲームプレイ中のスリープ・消灯・性能制限を徹底抑止"))
                    Text(tr("【多语言与本地化】新增英语与日语完整支持，支持系统语言跟随与应用内自由切换",
                            "Added full English and Japanese localization with real-time in-app switching",
                            "【多言語・日本語対応】英語および日本語の完全ローカライズを追加し、アプリ内でのリアルタイム切替に対応"))
                    Text(tr("【服务状态体检】新增软件服务与权限状态检测器，支持一键自动修复与历史残留服务清理",
                            "Added Software Service & Permission Health Inspector with 1-click repair and legacy cleanup",
                            "【サービス健康診断】特権ヘルパーとシステム権限の状態診断、過去の残存ファイルのワンクリッククリーンアップ"))
                    Text(tr("【辅助服务精简】辅助服务标识符精简为 macgametoolbox.helper，系统后台活动正确显示 App 图标",
                            "Streamlined helper to macgametoolbox.helper and bound native app icon in Login Items & Extensions",
                            "【ヘルパー最適化】ヘルパー識別子を macgametoolbox.helper に統一し、ログイン項目でアプリアイコンを正常表示"))
                    Text(tr("【纯 ARM64 分发】全面迁移至 Apple Silicon 纯原生构建，发布包统一采用无损 Zip 格式分发",
                            "Optimized exclusively for Apple Silicon ARM64 with lightweight Zip archive distribution",
                            "【ネイティブARM64】Apple Silicon専用の軽量高速ビルドに一本化し、Zip形式で配布"))
                }
                Section("3.0.7") {
                    Text(tr("HoYoGames 启动帮助部分功能修复", "Fixed parts of the HoYoGames Launch Assistant", "HoYoGames 起動アシスタントの不具合修正"))
                }
                Section("3.0.6") {
                    Text(tr("移除默认挂载路径数量限制，支持添加任意数量的默认路径", "Removed the default mount-path limit, allowing any number of default paths to be added", "デフォルトマウントパスの件数制限を撤廃"))
                    Text(tr("默认路径保存、重新加载和旧配置导入不再截断为三项", "Default paths are no longer truncated to three entries when saved, reloaded, or imported from legacy configuration", "マウントパスの保存・再読み込み時の上限を解除"))
                }
                Section("3.0.5") {
                    Text(tr("更新应用图标，采用铺满画布的蓝紫色背景", "Updated the app icon with a blue-purple background that fills the canvas", "アプリアイコンを刷新"))
                    Text(tr("移除磁盘挂载数量限制，支持选择、批量挂载和自动恢复任意数量的磁盘", "Removed the disk mount limit and added support for selecting, batch-mounting, and automatically restoring any number of volumes", "ディスク選択・一括マウントの上限を解除"))
                }
                Section("3.0.0") {
                    Text(tr("MetalHUD 新增最近 App 启动台，可快速重开、移除记录或选择其他 App", "Added a MetalHUD recent-app launcher with quick reopen, removal, and Other App selection", "MetalHUD 最近のゲームランチャーを追加"))
                    Text(tr("HoYoGames 启动帮助新增 10、15、20 秒等待时间", "Added 10, 15, and 20 second wait options to the HoYoGames Launch Assistant", "HoYoGames 待機時間の選択肢を追加"))
                }
            }
            .navigationTitle(tr("更新日志", "Changelog", "更新履歴"))
            .toolbar { Button(tr("完成", "Done", "完了")) { dismiss() } }
        }
        .frame(minWidth: 580, minHeight: 420)
    }
}

struct TutorialsView: View {
    @Environment(\.dismiss) private var dismiss

    private var links: [(String, String)] {
        let code = AppLanguage.resolvedLanguageCode
        if code == "zh-Hans" {
            return [
                ("Mac 玩游戏从入门到精通", "https://b23.tv/pEOGX4P"),
                ("CrossOver 零基础入门指南", "https://b23.tv/SlpOQoA"),
                ("CrossOver 全部教程合集", "https://b23.tv/V5xIKy4"),
                ("CrossOver 疑难解答合集", "https://b23.tv/8l2dLbN"),
                ("问题反馈与日志教程", "https://b23.tv/1UfRohG"),
                ("艾文的哔哩哔哩主页", "https://b23.tv/dV7YBJQ"),
                ("艾文的 YouTube 频道", "https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ")
            ]
        } else if code == "ja" {
            return [
                ("Mac ゲームプレイ入門〜応用ガイド", "https://b23.tv/pEOGX4P"),
                ("CrossOver 初心者向けセットアップガイド", "https://b23.tv/SlpOQoA"),
                ("CrossOver 完全チュートリアル集", "https://b23.tv/V5xIKy4"),
                ("CrossOver トラブルシューティング集", "https://b23.tv/8l2dLbN"),
                ("問題報告と診断ログの出力方法", "https://b23.tv/1UfRohG"),
                ("公式 Bilibili チャンネル", "https://b23.tv/dV7YBJQ"),
                ("公式 YouTube チャンネル", "https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ")
            ]
        }
        return [
            ("Mac Gaming: Beginner to Advanced", "https://b23.tv/pEOGX4P"),
            ("CrossOver Beginner's Guide", "https://b23.tv/SlpOQoA"),
            ("Complete CrossOver Tutorial Collection", "https://b23.tv/V5xIKy4"),
            ("CrossOver Troubleshooting Collection", "https://b23.tv/8l2dLbN"),
            ("Feedback and Log Tutorial", "https://b23.tv/1UfRohG"),
            ("Iven's Bilibili Channel", "https://b23.tv/dV7YBJQ"),
            ("Iven's YouTube Channel", "https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ")
        ]
    }

    var body: some View {
        NavigationStack {
            List(links, id: \.1) { title, address in
                Link(destination: URL(string: address)!) {
                    HStack(spacing: 16) {
                        Text(title).font(.system(size: 18, weight: .medium))
                        Spacer()
                        Image(systemName: "arrow.up.right.square").font(.title3)
                    }
                    .padding(.vertical, 10)
                }
            }
            .navigationTitle(tr("教程总导航", "Tutorial Hub", "チュートリアル・ガイド"))
            .toolbar { Button(tr("完成", "Done", "完了")) { dismiss() } }
        }
        .frame(minWidth: 620, minHeight: 500)
    }
}
