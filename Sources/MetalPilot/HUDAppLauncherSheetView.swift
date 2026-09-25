import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MetalPilotCore
#endif

public struct HUDAppLauncherSheetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 38, height: 38)
                    Image(systemName: "gamecontroller.fill")
                        .font(.title3.bold())
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("选择应用启动", "Launch Selected Apps", "選択アプリを起動"))
                        .font(.headline)
                    Text(tr("在下方单选或多选要启动的游戏/软件。点击启动按钮即可一键完成环境注入并批量启动，无需开启全局 HUD。",
                            "Select one or more games to launch with independent Metal HUD injection without enabling global HUD.",
                            "起動したいゲームを選択してください。グローバルHUDを有効化することなく、選択したゲームに独立してHUDを注入・一括起動します。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Control Bar
            HStack(spacing: 10) {
                Button {
                    model.addAppToHUDList()
                } label: {
                    Label(tr("添加新应用", "Add New App", "新しいアプリを追加"), systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                if !model.selectedHUDAppPaths.isEmpty {
                    Button(role: .destructive) {
                        withAnimation {
                            model.removeRecentMetalHUDApps(paths: model.selectedHUDAppPaths)
                        }
                    } label: {
                        Label(
                            tr("删除所选 (\(model.selectedHUDAppPaths.count))", "Delete Selected (\(model.selectedHUDAppPaths.count))", "選択項目を削除 (\(model.selectedHUDAppPaths.count))"),
                            systemImage: "trash"
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .controlSize(.small)
                }

                Spacer()

                Button(tr("全选", "Select All", "すべて選択")) {
                    model.selectedHUDAppPaths = Set(model.configuration.recentMetalHUDApps.map(\.path))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(tr("清空", "Clear Selection", "選択解除")) {
                    model.selectedHUDAppPaths.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Games List Box
            if model.configuration.recentMetalHUDApps.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "square.grid.3x1.folder.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text(tr("暂未添加任何游戏或应用程序", "No games or applications added yet", "登録されているゲームがありません"))
                        .font(.subheadline.bold())
                    Text(tr("点击上方「添加新应用」按钮，选择你的 Mac 游戏、CrossOver 或 Wine 程序进行添加与管理。",
                            "Click 'Add New App' above to select your Mac, CrossOver, or Wine games.",
                            "上の「新しいアプリを追加」からゲームを選択して登録してください。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(model.configuration.recentMetalHUDApps) { app in
                            gameRow(app)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 300)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            // Bottom Action Bar
            HStack {
                Text(tr("已选择 \(model.selectedHUDAppPaths.count) / \(model.configuration.recentMetalHUDApps.count) 款游戏",
                        "Selected \(model.selectedHUDAppPaths.count) / \(model.configuration.recentMetalHUDApps.count) games",
                        "\(model.selectedHUDAppPaths.count) / \(model.configuration.recentMetalHUDApps.count) 個のゲームを選択中"))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                Button(tr("取消", "Cancel", "キャンセル")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button {
                    let targets = Array(model.selectedHUDAppPaths)
                    dismiss()
                    model.launchSelectedHUDApps(targets)
                } label: {
                    Label(
                        tr("启动所选游戏 (\(model.selectedHUDAppPaths.count))", "Launch Selected (\(model.selectedHUDAppPaths.count))", "選択したゲームを起動 (\(model.selectedHUDAppPaths.count))"),
                        systemImage: "play.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.selectedHUDAppPaths.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 420)
    }

    private func gameRow(_ app: RecentMetalHUDApp) -> some View {
        let isSelected = model.selectedHUDAppPaths.contains(app.path)
        let hasCustomProfile = model.profileForApp(path: app.path) != nil
        let appIcon = NSWorkspace.shared.icon(forFile: app.path)

        return HStack(spacing: 12) {
            // Checkbox
            Button {
                if isSelected {
                    model.selectedHUDAppPaths.remove(app.path)
                } else {
                    model.selectedHUDAppPaths.insert(app.path)
                }
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)

            // App Icon
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 32, height: 32)
                .cornerRadius(6)

            // Name and path
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    if app.importedPreset != nil {
                        // Priority: an imported preset overrides both the per-app custom
                        // profile and the global default for this app's launches.
                        Text(tr("外部预设（优先）", "Imported Preset (takes priority)", "外部プリセット（優先）"))
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18))
                            .foregroundStyle(.orange)
                            .cornerRadius(3)
                    }
                    if hasCustomProfile {
                        Text(tr("专属方案", "Custom Profile", "個別設定"))
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .cornerRadius(3)
                    } else {
                        Text(tr("全局预设", "Global Default", "全体設定"))
                            .font(.system(size: 9))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.secondary)
                            .cornerRadius(3)
                    }
                }
                Text(app.path)
                    .font(.system(size: 10).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // Imported external HUD preset actions
            if let preset = app.importedPreset {
                Button {
                    model.removeImportedHUDPreset(forAppPath: app.path)
                } label: {
                    Text(tr("移除预设", "Remove Preset", "プリセットを削除"))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .controlSize(.small)
                .help(tr("当前使用外部预设：\(preset.displayName)（优先于专属方案与全局预设）",
                         "Using external preset: \(preset.displayName) (overrides custom/global profile)",
                         "外部プリセットを使用中：\(preset.displayName)（個別・全体設定より優先）"))
            } else {
                Button {
                    model.importExternalHUDPreset(forAppPath: app.path)
                } label: {
                    Text(tr("导入预设", "Import Preset", "プリセットを読込"))
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(tr("导入外部 Metal HUD 预设文件；导入后将优先于专属方案与全局预设",
                         "Import an external Metal HUD preset file; it will take priority over custom/global profiles",
                         "外部 Metal HUD プリセットを読み込みます。読み込み後は個別・全体設定より優先されます"))
            }

            // Delete App Button in Red Text
            Button(role: .destructive) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.selectedHUDAppPaths.remove(app.path)
                    model.removeRecentMetalHUDApp(app)
                }
            } label: {
                Text(tr("删除", "Delete", "削除"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.bordered)
            .tint(.red)
            .controlSize(.small)

            // Single Game Direct Launch Button
            Button {
                dismiss()
                model.launchRecordedAppWithMetalHUD(app.path)
            } label: {
                Label(tr("启动", "Launch", "起動"), systemImage: "play.fill")
                    .font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                model.selectedHUDAppPaths.remove(app.path)
            } else {
                model.selectedHUDAppPaths.insert(app.path)
            }
        }
    }
}
