import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MetalPilotCore
#endif

public struct SystemSectionView: View {
    @EnvironmentObject private var model: AppModel

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            GamingSectionHeader(
                icon: "gearshape.2.fill",
                title: tr("系统工具与偏好设置", "System Tools & Preferences", "システムツールと環境設定"),
                subtitle: tr("软件服务与系统权限检测、界面语言设置与核心服务诊断修复", "Software service and permission health inspection, language preferences, and diagnostics", "サービス・システム権限の診断、表示言語設定、システム診断と修復"),
                accentColor: .purple
            )

            // Preferences Box (Language)
            preferencesBox

            // Service & Permission Health Inspector Box
            systemHealthBox

            // Utilities & Info Grid
            HStack(spacing: 16) {
                tutorialBox
                changelogBox
            }

            // Diagnostics & Repair Box
            diagnosticsBox
        }
        .onAppear {
            if model.healthReport == nil {
                model.checkSystemHealth()
            }
        }
    }

    // MARK: - Preferences Box (Language)

    private var preferencesBox: some View {
        GroupBox(label:
            HStack(spacing: 8) {
                Label(tr("通用偏好设置与语言", "Preferences & Language", "一般設定と言語"), systemImage: "globe")
                    .font(.headline)
                    .foregroundStyle(.purple)
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Language Selection
                HStack(spacing: 12) {
                    Text(tr("界面语言：", "Language:", "表示言語："))
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()

                    Picker("", selection: Binding(
                        get: { model.configuration.languagePreference },
                        set: { model.setLanguagePreference($0) }
                    )) {
                        ForEach(AppLanguagePreference.allCases, id: \.self) { pref in
                            Text(pref.displayName).tag(pref)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
            }
            .padding(6)
        }
    }

    // MARK: - Service & Permission Health Box

    private var systemHealthBox: some View {
        let isHealthy = model.healthReport?.allHealthy ?? false
        let coexistenceEnabled = model.configuration.legacyHelperCoexistence
        let hasLegacy = !(model.healthReport?.legacyHelpersFound.isEmpty ?? true) && !coexistenceEnabled
        let hasWarnings = (model.healthReport?.items.contains { $0.status == .warning } ?? false)

        let badgeStyle: LiveStatusBadge.StatusType = isHealthy ? .active : (hasLegacy ? .warning : (hasWarnings ? .standby : .idle))
        let badgeTitle: String = isHealthy ? tr("全部正常", "All Healthy", "すべて正常") : (hasLegacy ? tr("发现历史残留", "Legacy Residuals", "過去の残存ファイルを検出") : tr("就绪 (按需授权)", "Ready (On-Demand)", "待機中 (オンデマンド)"))

        return GroupBox(label:
            HStack(spacing: 8) {
                Label(tr("软件服务与系统权限检测", "Software Service & Permission Health", "サービス・システム権限の診断"), systemImage: "shield.checkerboard")
                    .font(.headline)
                    .foregroundStyle(.purple)
                LiveStatusBadge(
                    badgeStyle,
                    title: badgeTitle
                )
            }
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("检测特权辅助服务 (XPC 通信)、系统后台运行权限与 Metal HUD 注入环境，支持一键体检与历史旧版本残留清理。",
                        "Inspects privileged helper XPC status, background items permission, and Metal HUD injection environment.",
                        "特権ヘルパーサービス（XPC通信）、システムバックグラウンド動作権限、Metal HUDフック環境を診断し、過去バージョンの残存ファイルのクリーンアップをサポートします。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                // Health Items List
                if let report = model.healthReport {
	                    VStack(spacing: 8) {
		                        ForEach(report.items) { item in
		                            HStack(alignment: .center, spacing: 12) {
		                                Image(systemName: item.status.iconName)
		                                    .foregroundStyle(item.status == .healthy ? .green : (item.status == .warning ? .orange : .red))
		                                    .font(.subheadline)

		                                VStack(alignment: .leading, spacing: 2) {
		                                    Text(tr(item.nameZh, item.nameEn, item.nameJa))
		                                        .font(.caption.bold())
		                                    Text(tr(item.detailZh, item.detailEn, item.detailJa))
		                                        .font(.caption2)
		                                        .foregroundStyle(.secondary)
		                                }

		                                Spacer()

		                                if item.nameZh.contains("屏幕录制") && !model.isScreenCapturePermissionGranted {
		                                    Button(tr("请求授权", "Authorize", "許可")) {
		                                        model.requestScreenRecordingPermission()
		                                    }
		                                    .buttonStyle(.borderedProminent)
		                                    .controlSize(.small)
		                                } else if item.nameZh.contains("辅助功能") && !model.isAccessibilityPermissionGranted {
		                                    Button(tr("请求授权", "Authorize", "許可")) {
		                                        model.requestAccessibilityPermission()
		                                    }
		                                    .buttonStyle(.borderedProminent)
		                                    .controlSize(.small)
		                                }
		                            }
		                            .padding(.horizontal, 10)
		                            .padding(.vertical, 8)
		                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
		                        }
	                    }

                    // Legacy Helper Banner (warning, or neutral note in side-by-side mode)
                    if !report.legacyHelpersFound.isEmpty {
                        if model.configuration.legacyHelperCoexistence {
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tr("旧版服务已按你的选择保留（共存模式）", "Legacy Service Kept by Your Choice (Side-by-Side)", "旧サービスは共存モードで保持されています"))
                                        .font(.caption.bold())
                                    Text(tr("已保留：\(report.legacyHelpersFound.joined(separator: ", "))。新旧服务互不影响；如需迁移到 metalpilot.helper，点击下方按钮后选择迁移。",
                                            "Kept: \(report.legacyHelpersFound.joined(separator: ", ")). Both services run independently; migrate to metalpilot.helper anytime via the button below.",
                                            "保持中：\(report.legacyHelpersFound.joined(separator: ", "))。新舊サービスは独立して動作します。移行は下のボタンからいつでも可能です。"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        } else {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(tr("检测到历史旧版本辅助服务残留", "Legacy Helper Residuals Detected", "過去バージョンのヘルパー残存ファイルを検出"))
                                        .font(.caption.bold())
                                    Text(tr("发现历史服务：\(report.legacyHelpersFound.joined(separator: ", "))。建议点击下方一键清理。",
                                            "Found: \(report.legacyHelpersFound.joined(separator: ", ")). Click cleanup below.",
                                            "検出されたサービス：\(report.legacyHelpersFound.joined(separator: ", "))。下のボタンでクリーンアップを推奨します。"))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text(tr("正在进行服务健康诊断…", "Inspecting system health…", "システム診断を実行中…"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Divider()

                // Action Controls
                HStack(spacing: 12) {
	                    let helperInstalled = FileManager.default.fileExists(atPath: "/Library/PrivilegedHelperTools/metalpilot.helper")
	                    Button {
	                        model.requestServiceRepair()
	                    } label: {
	                        Label(
	                            helperInstalled ? tr("一键重新注册与修复服务", "Re-register & Repair Service", "サービスの再登録と修復") : tr("手动安装特权辅助服务", "Install Privileged Helper", "特権ヘルパーを手動インストール"),
	                            systemImage: helperInstalled ? "sparkles" : "shield.badge.plus"
	                        )
	                    }
	                    .buttonStyle(.borderedProminent)
	                    .tint(.purple)
	                    .controlSize(.regular)

	                    Button {
	                        model.openBackgroundSettings()
	                    } label: {
	                        Label(tr("打开系统后台设置", "Open Login Items", "バックグラウンド設定を開く"), systemImage: "gearshape")
	                    }
	                    .buttonStyle(.bordered)
	                    .controlSize(.regular)

	                    Button {
	                        model.checkSystemHealth()
	                    } label: {
	                        Label(tr("刷新", "Refresh", "更新"), systemImage: "arrow.clockwise")
	                    }
	                    .buttonStyle(.bordered)
	                    .controlSize(.regular)
	                    .disabled(model.isCheckingHealth)

	                    Spacer()
	                }
	            }
	            .padding(6)
	        }
	    }

	    // MARK: - Tutorial & Changelog Boxes

	    private var tutorialBox: some View {
	        GroupBox(label: Label(tr("教程总导航", "Tutorial Hub", "チュートリアル・ガイド"), systemImage: "book.pages.fill").font(.headline)) {
	            VStack(alignment: .leading, spacing: 10) {
	                Text(tr("Mac 游戏运行、Wine 容器配置、GPTK 补丁教程", "Guides for Mac gaming, Wine bottles, and GPTK.", "Macゲーム環境構築、Wineボトル設定、GPTKパッチの解説"))
	                    .font(.caption)
	                    .foregroundStyle(.secondary)
	                Spacer(minLength: 4)
	                Button(tr("打开教程导航", "Open Hub", "ガイドを開く")) {
	                    model.showingTutorials = true
	                }
	                .controlSize(.small)
	            }
	            .padding(4)
	            .frame(maxWidth: .infinity, alignment: .leading)
	        }
	    }

	    private var changelogBox: some View {
	        GroupBox(label: Label(tr("更新日志", "Changelog", "更新履歴"), systemImage: "clock.arrow.circlepath").font(.headline)) {
	            VStack(alignment: .leading, spacing: 10) {
	                Text(tr("查看最新版本更新历史与功能改进记录", "View recent release changes and feature enhancements.", "最新バージョンの更新内容と機能改善履歴を確認"))
	                    .font(.caption)
	                    .foregroundStyle(.secondary)
	                Spacer(minLength: 4)
	                Button(tr("查看更新记录", "View Changelog", "履歴を確認")) {
	                    model.showingChangelog = true
	                }
	                .controlSize(.small)
	            }
	            .padding(4)
	            .frame(maxWidth: .infinity, alignment: .leading)
	        }
	    }

	    // MARK: - Diagnostics & Repair Box

	    private var diagnosticsBox: some View {
	        GroupBox {
	            HStack(spacing: 12) {
	                Image(systemName: "wrench.and.screwdriver.fill")
	                    .font(.system(size: 16))
	                    .foregroundStyle(.secondary)

	                Text(tr("遇到权限或执行异常？", "Encountered issues?", "権限や動作に問題がありますか？"))
	                    .font(.subheadline)
	                    .foregroundStyle(.secondary)

	                Spacer()

	                Button(tr("修复核心功能", "Repair Core", "コア機能を修復")) {
	                    model.repairCoreFeatures()
	                }
	                .controlSize(.small)

	                Button(tr("导出诊断日志", "Export Diagnostics", "診断ログを出力")) {
	                    model.requestDiagnosticsExport()
	                }
	                .controlSize(.small)
            }
            .padding(4)
        }
    }
}
