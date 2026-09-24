import AppKit
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

/// Transient launcher for running an app on a connected iPhone/iPad with a
/// process-scoped Metal HUD environment.
///
/// Scope of this first version:
/// - the Mac app only *drives* `xcrun devicectl`; it is not an iOS app;
/// - nothing here is persisted, and the privileged helper/XPC is not involved;
/// - a successful command is not proof that the HUD actually rendered, so the
///   UI says so explicitly.
struct IOSHUDLauncherSheetView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var appSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            HStack(alignment: .top, spacing: 0) {
                deviceColumn
                Divider()
                appColumn
            }
            .frame(maxHeight: .infinity)
            Divider()
            launchArgumentsBar
            footer
        }
        .padding(20)
        .frame(width: 820, height: 560)
        .sheet(item: $model.iosLaunchConfirmationApp) { app in
            IOSLaunchConfirmationView(app: app)
                .environmentObject(model)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: "iphone.gen3")
                    .font(.title3.bold())
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tr("为 iOS 游戏开启 Metal HUD", "Enable MetalHUD for an iOS Game", "iOS ゲームで Metal HUD を有効化"))
                    .font(.headline)
                Text(tr("通过 Xcode 的 devicectl 在已配对的 iPhone/iPad 上启动 App，并只向该进程注入 MTL_HUD_ENABLED=1。本功能不会修改 Package 平台，也不会写入配置。",
                        "Launches an app on a paired iPhone/iPad through Xcode's devicectl and injects MTL_HUD_ENABLED=1 into that launch only. Nothing is persisted.",
                        "Xcode の devicectl でペアリング済みの iPhone/iPad 上のアプリを起動し、そのプロセスにのみ MTL_HUD_ENABLED=1 を注入します。設定は保存されません。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
    }

    // MARK: - Device column

    private var deviceColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("iOS 设备", "iOS Devices", "iOS デバイス"))
                    .font(.headline)
                Spacer()
                Button {
                    model.refreshIOSDevices()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshingIOSDevices)
                .help(tr("刷新设备", "Refresh devices", "デバイスを更新"))
            }

            if model.isRefreshingIOSDevices && model.iosDevices.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.iosDeviceErrorMessage {
                actionableError(message, retry: { model.refreshIOSDevices() })
            } else if model.iosDevices.isEmpty {
                emptyState(
                    icon: "iphone.slash",
                    title: tr("未发现 iPhone/iPad", "No iPhone/iPad found", "iPhone/iPad が見つかりません"),
                    detail: tr("请用数据线或同一局域网连接设备，在设备上信任本机，并在 Xcode 中完成配对后刷新。",
                               "Connect the device (cable or same network), trust this Mac on the device, pair it in Xcode, then refresh.",
                               "デバイスを接続し、この Mac を信頼し、Xcode でペアリングしてから更新してください。")
                )
            } else {
                List(selection: Binding(
                    get: { model.selectedIOSDeviceID },
                    set: { model.selectIOSDevice($0) }
                )) {
                    ForEach(model.iosDevices) { device in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(device.displayName)
                            if !device.detailText.isEmpty {
                                Text(device.detailText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .tag(Optional(device.id))
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.trailing, 14)
        .frame(width: 280)
    }

    // MARK: - App column

    private var appColumn: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("设备上的应用程序", "Apps on Device", "デバイス上のアプリ"))
                    .font(.headline)
                Spacer()
                Button {
                    model.refreshIOSApps()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(model.selectedIOSDeviceID == nil || model.isRefreshingIOSApps)
                .help(tr("刷新应用", "Refresh apps", "アプリを更新"))
            }

            TextField(tr("搜索应用名称或包名", "Search app name or bundle ID", "アプリ名またはバンドル ID で検索"), text: $appSearchText)
                .textFieldStyle(.roundedBorder)

            if model.selectedIOSDeviceID == nil {
                emptyState(
                    icon: "iphone",
                    title: tr("先选择设备", "Select a device first", "先にデバイスを選択してください"),
                    detail: nil
                )
            } else if model.isRefreshingIOSApps && model.iosApps.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = model.iosAppErrorMessage {
                actionableError(message, retry: { model.refreshIOSApps() })
            } else if model.iosApps.isEmpty {
                emptyState(
                    icon: "app.dashed",
                    title: tr("未读取到应用", "No apps found", "アプリが見つかりません"),
                    detail: tr("刷新后仍为空时，请确认设备已解锁、已连接且 Xcode 可访问该设备。",
                               "If it stays empty, confirm the device is unlocked, connected, and reachable by Xcode.",
                               "空のままの場合は、デバイスのロック解除・接続・Xcode からのアクセス可否を確認してください。")
                )
            } else if filteredIOSApps.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    title: tr("未找到匹配的应用", "No matching apps", "一致するアプリがありません"),
                    detail: tr("可按应用名称或包名的一部分进行搜索。",
                               "Search by any part of the app name or bundle ID.",
                               "アプリ名またはバンドル ID の一部で検索できます。")
                )
            } else {
                List(selection: $model.selectedIOSBundleIdentifier) {
                    ForEach(filteredIOSApps) { app in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.displayName)
                            Text(app.version.isEmpty ? app.bundleIdentifier : "\(app.bundleIdentifier) · \(app.version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .tag(Optional(app.bundleIdentifier))
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.leading, 14)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Launch arguments

    private var launchArgumentsBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(tr("本次启动参数（可选）", "Launch arguments for this session (optional)", "今回の起動引数（任意）"))
                    .font(.subheadline.weight(.semibold))
                Text(tr("每行一个参数，仅在本次会话生效，不会保存。", "One argument per line. Applies to this session only and is never saved.", "1 行に 1 引数。今回のセッションのみ有効で保存されません。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !model.iosLaunchArgumentsText.isEmpty {
                    Button(tr("清空", "Clear", "クリア")) {
                        model.iosLaunchArgumentsText = ""
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                }
            }
            TextEditor(text: $model.iosLaunchArgumentsText)
                .font(.body.monospaced())
                .frame(height: 62)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(tr("启动会先终止该 App 的现有实例（--terminate-existing），未保存的游戏进度可能丢失。devicectl 返回成功只代表命令已被接受，请以设备画面中的 HUD 是否出现为准。",
                        "Launching terminates any existing instance first (--terminate-existing); unsaved progress may be lost. A successful devicectl run only means the command was accepted — confirm the HUD on the device screen.",
                        "起動時に既存のインスタンスを終了します（--terminate-existing）。未保存の進行が失われる可能性があります。devicectl の成功はコマンド受理を意味するだけで、HUD 表示は実機で確認してください。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Text(selectedAppDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(tr("带 MetalHUD 启动", "Launch with MetalHUD", "MetalHUD 付きで起動")) {
                    if let app = selectedApp {
                        model.requestIOSLaunch(with: app)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!model.canLaunchIOSApp)
            }
        }
    }

    // MARK: - Helpers

    private var selectedApp: IOSInstalledApp? {
        guard let bundleIdentifier = model.selectedIOSBundleIdentifier else { return nil }
        return model.iosApps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    private var selectedAppDescription: String {
        guard let deviceID = model.selectedIOSDeviceID else {
            return tr("请选择设备与要启动的 App", "Select a device and an app to launch", "デバイスと起動するアプリを選択してください")
        }
        guard let bundleIdentifier = model.selectedIOSBundleIdentifier else {
            return tr("已选择设备：\(deviceID)", "Device selected: \(deviceID)", "選択中のデバイス：\(deviceID)")
        }
        return "\(deviceID) → \(bundleIdentifier)"
    }

    private var filteredIOSApps: [IOSInstalledApp] {
        let query = appSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.iosApps }
        return model.iosApps.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.bundleIdentifier.localizedCaseInsensitiveContains(query)
        }
    }

    private func emptyState(icon: String, title: String, detail: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }

    private func actionableError(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(tr("重试", "Retry", "再試行"), action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 12)
    }
}

/// Explicit pre-launch confirmation. Shown on every launch because the command
/// always terminates an existing instance of the selected app.
private struct IOSLaunchConfirmationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let app: IOSInstalledApp

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(tr("确认带 MetalHUD 启动", "Confirm launch with MetalHUD", "MetalHUD 付き起動の確認"))
                    .font(.title3.bold())
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(app.displayName).font(.headline)
                Text(app.bundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            VStack(alignment: .leading, spacing: 8) {
                labeledRisk(
                    icon: "xmark.octagon.fill",
                    title: tr("会先终止正在运行的实例", "Terminates the running instance first", "実行中のインスタンスを先に終了します"),
                    detail: tr("命令固定携带 --terminate-existing。若游戏正在运行，未保存的进度可能丢失。",
                               "The command always passes --terminate-existing. If the game is running, unsaved progress may be lost.",
                               "コマンドは常に --terminate-existing を付与します。ゲーム実行中の場合、未保存の進行が失われる可能性があります。")
                )
                labeledRisk(
                    icon: "checkmark.seal",
                    title: tr("成功 ≠ HUD 已显示", "Success ≠ HUD rendered", "成功 ≠ HUD 表示"),
                    detail: tr("devicectl 返回 0 只说明命令被接受；是否真正绘制 HUD 需要你在设备屏幕上确认。",
                               "A devicectl exit code of 0 only means the command was accepted; verify the HUD on the device screen.",
                               "devicectl の終了コード 0 はコマンド受理を意味するだけです。HUD の描画は実機で確認してください。")
                )
            }

            if !model.iosLaunchArguments.isEmpty {
                Text(tr("本次将传入 \(model.iosLaunchArguments.count) 个启动参数。",
                        "\(model.iosLaunchArguments.count) launch argument(s) will be passed this time.",
                        "今回 \(model.iosLaunchArguments.count) 個の起動引数を渡します。"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack {
                Spacer()
                Button(tr("取消", "Cancel", "キャンセル")) {
                    model.cancelIOSLaunch()
                }
                .keyboardShortcut(.cancelAction)
                Button(tr("终止并启动", "Terminate and Launch", "終了して起動")) {
                    model.confirmIOSLaunch()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding(24)
        .frame(width: 560, height: 380)
    }

    private func labeledRisk(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
