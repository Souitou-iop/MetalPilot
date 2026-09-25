#if SWIFT_PACKAGE
import MetalPilotCore
#endif
import SwiftUI

struct DiskManagerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(tr("磁盘挂载", "Volume Mounting", "ディスクマウント")).font(.title.bold())
                    Text(tr("启动磁盘已自动排除。", "The startup disk is excluded automatically.", "起動ディスクは自動的に除外されます。")).foregroundStyle(.secondary)
                }
                Spacer()
                Button(tr("刷新", "Refresh", "更新")) { model.loadDisks() }
                Button(tr("完成", "Done", "完了")) { dismiss() }
            }

            GroupBox {
                Toggle(isOn: Binding(
                    get: { model.configuration.automaticallyRestoreMountsOnLaunch },
                    set: { model.setAutomaticallyRestoreMountsOnLaunch($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(tr("开启应用时自动恢复上次挂载（可配合开机自启动实现开机自动挂载）",
                                "Restore previous mounts when the app opens (use with Launch at Login for automatic mounting after startup)",
                                "アプリ起動時に前回のマウントを自動復元（ログイン項目と併用で起動時自動マウント）"))
                        Text(tr("开启后每秒自动检测可用磁盘，应用开启 10 秒后恢复上次自定义挂载。推出或卸载磁盘不会清除记录；仅“恢复默认挂载”会停止下次恢复。",
                                "Checks for available volumes every second and restores the previous custom mount 10 seconds after launch. Ejecting or unmounting does not clear the record; only Restore Default stops the next restoration.",
                                "有効時、接続ディスクを毎秒検出して起動10秒後に復元します。取り出しやアンマウントでは記録は消去されず、「デフォルトに戻す」を実行した場合のみ次回以降の復元を停止します。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if model.disks.isEmpty {
                ContentUnavailableView(
                    tr("未发现可用卷", "No Available Volumes", "利用可能なボリュームがありません"),
                    systemImage: "externaldrive.badge.questionmark",
                    description: Text(tr("连接外置磁盘后刷新", "Connect an external volume and refresh", "外部ディスクを接続して更新してください"))
                )
            } else {
                List {
                    Section(tr("默认路径", "Default Paths", "デフォルトパス")) {
                        ForEach(model.configuration.defaultPaths, id: \.self) { path in
                            HStack {
                                Text(path).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Button(tr("删除", "Delete", "削除"), role: .destructive) { model.deleteDefaultPath(path) }
                            }
                        }
                        if model.configuration.defaultPaths.count < ConfigurationStore.maxDefaultPaths {
                            Button(tr("添加默认路径", "Add Default Path", "デフォルトパスを追加")) { model.addDefaultPath() }
                        }
                    }
                    if !model.configuration.diskPresets.isEmpty {
                        Section(tr("磁盘预设", "Volume Presets", "ボリュームプリセット")) {
                            ForEach(model.configuration.diskPresets, id: \.diskIdentifier) { preset in
                                HStack {
                                    Text(preset.diskIdentifier)
                                    Text(preset.mountPath ?? tr("未绑定路径", "No path assigned", "パス未設定")).foregroundStyle(.secondary).lineLimit(1)
                                    Spacer()
                                    Button(tr("删除", "Delete", "削除"), role: .destructive) { model.deleteDiskPreset(preset.diskIdentifier) }
                                }
                            }
                        }
                    }
                    Section(tr("可用磁盘", "Available Volumes", "利用可能なディスク")) {
                        ForEach(model.disks) { disk in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Toggle(isOn: selectedBinding(disk.id)) {
                                        VStack(alignment: .leading) {
                                            Text(disk.name).font(.headline)
                                            Text("\(disk.id) · \(disk.fileSystem) · \(ByteCountFormatter.string(fromByteCount: Int64(disk.size), countStyle: .file))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    .toggleStyle(.checkbox)
                                    Spacer()
                                    if disk.isInternal { Text(tr("内置", "Internal", "内蔵")).font(.caption).foregroundStyle(.orange) }
                                }
                                if model.selectedDiskIDs.contains(disk.id) {
                                    HStack {
                                        TextField(tr("挂载路径", "Mount path", "マウントパス"), text: pathBinding(disk.id))
                                        Button(tr("浏览", "Browse", "参照")) { model.choosePath(for: disk.id) }
                                        if !model.configuration.defaultPaths.isEmpty {
                                            Menu(tr("默认路径", "Defaults", "プリセットパス")) {
                                                ForEach(model.configuration.defaultPaths, id: \.self) { path in
                                                    Button(path) { model.diskPaths[disk.id] = path }
                                                }
                                            }
                                        }
                                        Button(tr("保存预设", "Save Preset", "プリセット保存")) { model.saveDiskPreset(disk.id) }
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                        }
                    }
                }
            }

            HStack {
                Text(tr("已选择 \(model.selectedDiskIDs.count)", "Selected \(model.selectedDiskIDs.count)", "選択中: \(model.selectedDiskIDs.count) 件")).foregroundStyle(.secondary)
                Spacer()
                Button(tr("恢复默认挂载", "Restore Default", "デフォルトに戻す")) { model.restoreSelectedDisks() }.disabled(model.selectedDiskIDs.isEmpty)
                Button(tr("挂载到指定路径", "Mount", "指定パスにマウント")) { model.mountSelectedDisks() }
                    .buttonStyle(.borderedProminent).disabled(model.selectedDiskIDs.isEmpty)
            }
        }
        .padding(24).frame(minWidth: 760, minHeight: 540)
    }

    private func selectedBinding(_ id: String) -> Binding<Bool> {
        Binding {
            model.selectedDiskIDs.contains(id)
        } set: { selected in
            if selected {
                model.selectedDiskIDs.insert(id)
            } else {
                model.selectedDiskIDs.remove(id)
            }
        }
    }

    private func pathBinding(_ id: String) -> Binding<String> {
        Binding(get: { model.diskPaths[id, default: ""] }, set: { model.diskPaths[id] = $0 })
    }
}
