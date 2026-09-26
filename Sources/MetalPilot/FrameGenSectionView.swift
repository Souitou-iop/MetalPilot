import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MetalPilotCore
#endif

public struct FrameGenSectionView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedPreset: ScalingPreset = .balancedGaming

    public init() {}

    public enum ScalingPreset: String, CaseIterable, Identifiable {
        case balancedGaming = "balancedGaming"
        case maxFPS = "maxFPS"
        case ultraQuality = "ultraQuality"
        case emulatorPixel = "emulatorPixel"

        public var id: String { rawValue }

        public var titleZh: String {
            switch self {
            case .balancedGaming: return "3A 游戏均衡 (2x 补帧 + 75% 超分)"
            case .maxFPS: return "极限帧率 (4x 外推 + 50% 性能超分)"
            case .ultraQuality: return "原生画质增强 (SMAA + CAS 锐化)"
            case .emulatorPixel: return "模拟器与复古 (2x 外推 + 原生缩放)"
            }
        }

        public var titleEn: String {
            switch self {
            case .balancedGaming: return "3A Balanced (2x FG + 75% Scale)"
            case .maxFPS: return "Max FPS (4x FG + 50% Scale)"
            case .ultraQuality: return "Ultra Quality (SMAA + CAS)"
            case .emulatorPixel: return "Emulator / Retro (2x FG + Native)"
            }
        }

        public var titleJa: String {
            switch self {
            case .balancedGaming: return "3A バランス (2x 補正 + 75% 超解像)"
            case .maxFPS: return "最大フレームレート (4x 外挿 + 50% 超解像)"
            case .ultraQuality: return "最高画質強化 (SMAA + CAS)"
            case .emulatorPixel: return "エミュレータ・レトロ (2x 外挿 + 等倍)"
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            GamingSectionHeader(
                icon: "sparkles.tv",
                title: tr("画质超分与动态补帧", "Resolution Scaling & Frame Generation", "超解像スケーリングと動的補フレーム"),
                subtitle: tr("结合 MetalGoose 与 MetalDuck 优势：零延迟媒体引擎运动外推、MetalFX 空间超分辨率、CAS 锐化与 SMAA 抗锯齿",
                           "Combining MetalGoose & MetalDuck: Zero-latency hardware motion extrapolation, MetalFX spatial upscaling, CAS sharpening & SMAA",
                           "MetalGooseとMetalDuckの長所を融合：ゼロ遅延ハードウェア運動外挿、MetalFX超解像、CAS鮮鋭化、SMAAアンチエイリアス"),
                accentColor: .purple
            )

            // Target Window & Master Activation Box
            targetWindowAndActivationBox

            // Presets Box
            presetsBox

            // Frame Generation Settings Box
            frameGenSettingsBox

            // Spatial Upscaling & Anti-Aliasing Box
            upscalingAndAABox

            // Cursor & Control Guidance Box
            cursorAndShortcutBox
        }
        .onAppear {
            if model.isScreenCapturePermissionGranted && model.availableWindows.isEmpty {
                model.refreshAvailableWindows()
            }
        }
    }

    // MARK: - Target Window & Master Activation Box

    private var targetWindowAndActivationBox: some View {
        GroupBox(label:
            HStack(spacing: 8) {
                Label(tr("目标游戏窗口与运行状态", "Target Window & Status", "対象ゲームウィンドウと状態"), systemImage: "macwindow.on.rectangle")
                    .font(.headline)
                    .foregroundStyle(.purple)
                LiveStatusBadge(
                    model.isScalingActive ? .active : .standby,
                    title: model.isScalingActive ? tr("补帧与超分运行中", "Active", "実行中") : tr("未开启", "Standby", "待機中")
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("选择运行中的游戏或模拟器窗口。启动后将通过非侵入式 Metal 叠加层进行零延迟运动外推与画质增强。",
                        "Select an active game or emulator window. Non-invasive Metal overlay applies zero-latency frame generation and upscaling.",
                        "実行中のゲームまたはエミュレータウィンドウを選択します。非侵入型Metalオーバーレイによりゼロ遅延補フレームと画質向上を適用します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !model.isScreenCapturePermissionGranted {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(tr("画质超分与补帧需使用屏幕录制权限捕获游戏画面。点击右侧完成授权：",
                                "Screen Recording permission is required to capture window content for frame generation.",
                                "補フレーム機能には画面収録権限が必要です。右側のボタンから許可してください："))
                            .font(.caption)
                            .foregroundStyle(.primary)

                        Spacer()

                        Button(tr("请求授权", "Request Access", "許可をリクエスト")) {
                            model.requestScreenRecordingPermission()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(tr("系统设置", "Settings", "システム設定")) {
                            model.openScreenRecordingSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                Divider()

                HStack(spacing: 12) {
                    Picker(tr("目标窗口：", "Target Window:", "対象ウィンドウ:"), selection: $model.selectedWindowID) {
                        if model.availableWindows.isEmpty {
                            Text(tr("未选择或未刷新窗口", "No active windows selected", "ウィンドウ未選択")).tag(Optional<CGWindowID>.none)
                        } else {
                            ForEach(model.availableWindows) { win in
                                Text("\(win.appName) - \(win.title)").tag(Optional(win.id))
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 340)

                    Button {
                        if model.isScreenCapturePermissionGranted {
                            model.refreshAvailableWindows()
                        } else {
                            model.requestScreenRecordingPermission()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(tr("刷新窗口列表", "Refresh Windows", "ウィンドウ一覧を更新"))

                    Spacer()

                    Button {
                        model.toggleScaling()
                    } label: {
                        Label(
                            model.isScalingActive ? tr("停止画质增强与补帧", "Stop Scaling & FG", "補フレームを停止") : tr("启动画质超分与补帧 (⌘⇧T)", "Start Scaling & FG (⌘⇧T)", "補フレームを開始 (⌘⇧T)"),
                            systemImage: model.isScalingActive ? "stop.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.isScalingActive ? .red : .purple)
                    .controlSize(.regular)
                }
            }
            .padding(6)
        }
    }

    // MARK: - Presets Box

    private var presetsBox: some View {
        GroupBox(label: Label(tr("快捷场景预设", "Quick Profiles", "プリセット設定"), systemImage: "slider.horizontal.3").font(.headline)) {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 10) {
                    ForEach(ScalingPreset.allCases) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            Text(tr(preset.titleZh, preset.titleEn, preset.titleJa))
                                .font(.body.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 34)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.bordered)
                        .tint(selectedPreset == preset ? .purple : .secondary)
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: - Frame Generation Settings Box

    private var frameGenSettingsBox: some View {
        GroupBox(label: Label(tr("动态插帧 / 补帧引擎配置", "Frame Generation Settings", "動的補フレームエンジン設定"), systemImage: "sparkles").font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Text(tr("补帧算法模式：", "Frame Gen Mode:", "補フレームモード:"))
                        .font(.subheadline.bold())

                    Picker("", selection: Binding(
                        get: { model.configuration.scalingSettings.frameGenMode },
                        set: {
                            var s = model.configuration.scalingSettings
                            s.frameGenMode = $0
                            model.updateScalingSettings(s)
                        }
                    )) {
                        ForEach(FrameGenMode.allCases) { mode in
                            Text(tr(mode.titleZh, mode.titleEn, mode.titleJa)).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 320)
                }

                Toggle(isOn: Binding(
                    get: { model.configuration.scalingSettings.sceneCutDetectionEnabled },
                    set: {
                        var s = model.configuration.scalingSettings
                        s.sceneCutDetectionEnabled = $0
                        model.updateScalingSettings(s)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("自适应 6-Sigma 场景剪辑保护 (Scene-Cut Detection)", "Adaptive 6-Sigma Scene-Cut Detection", "適応型 6-Sigma シーンチェンジ保護"))
                            .font(.subheadline)
                        Text(tr("实时监测镜头切换与画面突变，在场景瞬切时自动回退为直通渲染，彻底杜绝镜头切换形变撕裂。",
                                "Monitors frame deltas and falls back to passthrough during cuts to prevent morphing.",
                                "カメラ切り替えや画面の急変を検知し、シーンチェンジ時のモーフィングや歪みを完全に防止します。"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: - Spatial Upscaling & Anti-Aliasing Box

    private var upscalingAndAABox: some View {
        GroupBox(label: Label(tr("MetalFX 空间超分辨率与后处理画质", "MetalFX Spatial Upscaling & Post-Processing", "MetalFX 超解像とポストプロセス画質"), systemImage: "square.2.layers.3d.top.filled").font(.headline)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    Text(tr("渲染缩放比例：", "Render Scale:", "レンダリング解像度:"))
                        .font(.subheadline.bold())

                    Picker("", selection: Binding(
                        get: { model.configuration.scalingSettings.renderScale },
                        set: {
                            var s = model.configuration.scalingSettings
                            s.renderScale = $0
                            model.updateScalingSettings(s)
                        }
                    )) {
                        ForEach(ScalingRenderScale.allCases) { scale in
                            Text(tr(scale.titleZh, scale.titleEn, scale.titleJa)).tag(scale)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 240)
                }

                HStack(spacing: 16) {
                    Text(tr("抗锯齿方案：", "Anti-Aliasing:", "アンチエイリアス:"))
                        .font(.subheadline.bold())

                    Picker("", selection: Binding(
                        get: { model.configuration.scalingSettings.aaMode },
                        set: {
                            var s = model.configuration.scalingSettings
                            s.aaMode = $0
                            model.updateScalingSettings(s)
                        }
                    )) {
                        ForEach(ScalingAAMode.allCases) { mode in
                            Text(tr(mode.titleZh, mode.titleEn, mode.titleJa)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: .infinity)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { model.configuration.scalingSettings.casEnabled },
                        set: {
                            var s = model.configuration.scalingSettings
                            s.casEnabled = $0
                            model.updateScalingSettings(s)
                        }
                    )) {
                        Text(tr("启用 CAS 对比度自适应锐化 (Contrast-Adaptive Sharpening)", "Enable CAS Sharpening", "CAS コントラスト適応型鮮鋭化を有効化"))
                            .font(.subheadline)
                    }

                    if model.configuration.scalingSettings.casEnabled {
                        HStack {
                            Text(tr("锐化强度：\(Int(model.configuration.scalingSettings.sharpness * 100))%",
                                    "Sharpness: \(Int(model.configuration.scalingSettings.sharpness * 100))%",
                                    "鮮鋭化強度: \(Int(model.configuration.scalingSettings.sharpness * 100))%"))
                                .font(.caption.monospaced())
                                .frame(width: 140, alignment: .leading)

                            Slider(
                                value: Binding(
                                    get: { Double(model.configuration.scalingSettings.sharpness) },
                                    set: {
                                        var s = model.configuration.scalingSettings
                                        s.sharpness = Float($0)
                                        model.updateScalingSettings(s)
                                    }
                                ),
                                in: 0.0...1.0,
                                step: 0.05
                            )
                        }
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: - Cursor & Shortcut Guidance Box

    private var cursorAndShortcutBox: some View {
        GroupBox(label: Label(tr("控制与快捷键说明", "Controls & Global Shortcuts", "操作とグローバルショートカット"), systemImage: "keyboard.fill").font(.headline)) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 20) {
                        HStack(spacing: 6) {
                            Text("⌘ + ⇧ + T")
                                .font(.system(.caption, design: .monospaced).bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                            Text(tr("全局一键开启 / 暂停超分补帧", "Toggle Scaling & Frame Gen", "補フレームの開始/停止"))
                                .font(.caption)
                        }

                        HStack(spacing: 6) {
                            Text("⌘ + ⇧ + C")
                                .font(.system(.caption, design: .monospaced).bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                            Text(tr("锁定 / 解锁鼠标光标约束", "Lock / Unlock Mouse Cursor", "マウスカーソル拘束の切替"))
                                .font(.caption)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("⌘ + ⌥ + ⇧ + Esc")
                            .font(.system(.caption, design: .monospaced).bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(4)
                        Text(tr("紧急回退：立即移除覆盖层", "Emergency rollback: remove overlay immediately", "緊急復帰：オーバーレイを即時解除"))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: - Preset Application

    private func applyPreset(_ preset: ScalingPreset) {
        selectedPreset = preset
        var s = model.configuration.scalingSettings
        switch preset {
        case .balancedGaming:
            s.frameGenMode = .extrapolation2x
            s.renderScale = .scale75
            s.aaMode = .smaa
            s.casEnabled = true
            s.sharpness = 0.5
            s.sceneCutDetectionEnabled = true
        case .maxFPS:
            s.frameGenMode = .extrapolation4x
            s.renderScale = .scale50
            s.aaMode = .fxaa
            s.casEnabled = true
            s.sharpness = 0.7
            s.sceneCutDetectionEnabled = true
        case .ultraQuality:
            s.frameGenMode = .off
            s.renderScale = .scale100
            s.aaMode = .smaa
            s.casEnabled = true
            s.sharpness = 0.6
            s.sceneCutDetectionEnabled = true
        case .emulatorPixel:
            s.frameGenMode = .extrapolation2x
            s.renderScale = .scale100
            s.aaMode = .none
            s.casEnabled = false
            s.sceneCutDetectionEnabled = true
        }
        model.updateScalingSettings(s)
    }
}
