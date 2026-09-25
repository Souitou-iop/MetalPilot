import AppKit
import SwiftUI

@main
struct MetalPilotApp: App {
    @NSApplicationDelegateAdaptor(MetalPilotApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model: AppModel

    init() {
        let appModel = AppModel()
        _model = StateObject(wrappedValue: appModel)
        DispatchQueue.main.async {
            MenuCommandCoordinator.shared.install(model: appModel)
            StatusBarController.shared.setup(model: appModel)
        }
    }

    var body: some Scene {
        Window(tr("MetalPilot", "MetalPilot", "MetalPilot"), id: "main") {
            ZStack {
                DashboardView()
                    .environmentObject(model)
                MainWindowBridge()
            }
            .frame(minWidth: 900, minHeight: 650)
        }
        .defaultSize(width: 1040, height: 760)
        .commandsReplaced {
            CommandGroup(replacing: .appInfo) {
                Button(tr("关于 MetalPilot", "About MetalPilot", "MetalPilot について")) {
                    MenuCommandCoordinator.shared.showAboutPanel()
                }
            }
            CommandGroup(replacing: .appTermination) {
                Button(tr("退出 MetalPilot", "Quit MetalPilot", "MetalPilot を終了")) {
                    MenuCommandCoordinator.shared.quitApplication()
                }
                .keyboardShortcut("q")
            }
            CommandGroup(replacing: .windowSize) { }
        }
        .commands {
            CommandMenu(tr("帮助", "Help", "ヘルプ")) {
                Button(tr("导出诊断日志", "Export Diagnostics", "診断ログを出力")) { MenuCommandCoordinator.shared.exportDiagnostics() }
                Button(tr("修复核心功能", "Repair Core Features", "コア機能を修復")) { MenuCommandCoordinator.shared.repairCoreFeatures() }
                Button(tr("教程总导航", "Tutorials", "チュートリアル・ガイド")) { MenuCommandCoordinator.shared.showTutorials() }
            }
        }
    }
}

struct MainWindowBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                MenuCommandCoordinator.shared.openWindowAction = {
                    openWindow(id: "main")
                }
            }
    }
}

@MainActor
final class MainWindowDelegate: NSObject, NSWindowDelegate {
    static let shared = MainWindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        sender.isReleasedWhenClosed = false
        DispatchQueue.main.async {
            MenuCommandCoordinator.shared.updateDockVisibility()
        }
        return false
    }
}

final class MetalPilotApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if MenuCommandCoordinator.shared.consumeExplicitQuitRequest() {
            return .terminateNow
        }
        if NSAppleEventManager.shared().currentAppleEvent?.eventID == 0x7175_6974 {
            return .terminateNow
        }
        return .terminateCancel
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        MenuCommandCoordinator.shared.reopenMainWindow()
        return true
    }
}

@MainActor
final class MenuCommandCoordinator: NSObject {
    static let shared = MenuCommandCoordinator()
    private weak var model: AppModel?
    var openWindowAction: (() -> Void)?
    private var keyMonitor: Any?
    private var explicitQuitRequested = false
    private var menuObserverInstalled = false
    private var windowObserverInstalled = false
    private var isReorderingMenus = false

    func install(model: AppModel) {
        self.model = model
        installMenuOrderObserverIfNeeded()
        installWindowLifecycleObservers()
        stabilizeTopLevelMenuOrder()
        updateDockVisibility()
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let relevantModifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard relevantModifiers == .command else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "w":
                self?.closeWindow()
                return nil
            case "q":
                self?.quitApplication()
                return nil
            default:
                return event
            }
        }
    }

    private func installWindowLifecycleObservers() {
        guard !windowObserverInstalled else { return }
        windowObserverInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel),
              window.canBecomeMain else { return }
        if window.delegate == nil || window.delegate !== MainWindowDelegate.shared {
            window.delegate = MainWindowDelegate.shared
        }
        updateDockVisibility()
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is NSPanel),
              window.canBecomeMain else { return }
        DispatchQueue.main.async { [weak self] in
            self?.updateDockVisibility()
        }
    }

    func updateDockVisibility() {
        let hasVisibleMainWindow = NSApp.windows.contains { window in
            !(window is NSPanel) && window.canBecomeMain && window.isVisible
        }
        if hasVisibleMainWindow {
            if NSApp.activationPolicy() != .regular {
                NSApp.setActivationPolicy(.regular)
            }
        } else {
            if NSApp.activationPolicy() != .accessory {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    private func installMenuOrderObserverIfNeeded() {
        guard !menuObserverInstalled else { return }
        menuObserverInstalled = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainMenuDidAddItem(_:)),
            name: NSMenu.didAddItemNotification,
            object: nil
        )
    }

    @objc private func mainMenuDidAddItem(_ notification: Notification) {
        guard let changedMenu = notification.object as? NSMenu,
              changedMenu === NSApp.mainMenu else { return }
        stabilizeTopLevelMenuOrder()
    }

    private func stabilizeTopLevelMenuOrder() {
        guard !isReorderingMenus, let menu = NSApp.mainMenu, !menu.items.isEmpty else { return }
        isReorderingMenus = true
        defer { isReorderingMenus = false }

        if let viewIndex = menu.items.firstIndex(where: { $0.title == tr("显示", "View", "表示") }) {
            menu.removeItem(at: viewIndex)
        }
        if let windowIndex = menu.items.firstIndex(where: { $0.title == tr("窗口", "Window", "ウィンドウ") }),
           let helpIndex = menu.items.firstIndex(where: { $0.title == tr("帮助", "Help", "ヘルプ") }),
           helpIndex < windowIndex {
            let helpItem = menu.items[helpIndex]
            menu.removeItem(at: helpIndex)
            if let newWindowIndex = menu.items.firstIndex(where: { $0.title == tr("窗口", "Window", "ウィンドウ") }) {
                let targetIndex = min(menu.items.count, newWindowIndex + 1)
                menu.insertItem(helpItem, at: targetIndex)
            } else {
                menu.addItem(helpItem)
            }
        }
    }

    func showAboutPanel() {
        NSApp.orderFrontStandardAboutPanel(options: [:])
    }

    func quitApplication() {
        explicitQuitRequested = true
        NSApp.terminate(nil)
    }

    func consumeExplicitQuitRequest() -> Bool {
        guard explicitQuitRequested else { return false }
        explicitQuitRequested = false
        return true
    }

    static func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }

    func minimize() { (NSApp.keyWindow ?? NSApp.mainWindow)?.miniaturize(nil) }
    func closeWindow() {
        let mainWin = (NSApp.keyWindow ?? NSApp.mainWindow) ?? NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }
        mainWin?.orderOut(nil)
        DispatchQueue.main.async { [weak self] in
            self?.updateDockVisibility()
        }
    }
    func reopenMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        var found = false
        for window in NSApp.windows where !(window is NSPanel) && window.canBecomeMain {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            window.setIsVisible(true)
            window.orderFrontRegardless()
            found = true
        }
        if !found {
            openWindowAction?()
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.updateDockVisibility()
        }
    }
    func zoom() { (NSApp.keyWindow ?? NSApp.mainWindow)?.performZoom(nil) }
    func toggleFullScreen() { (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil) }
    func center() { (NSApp.keyWindow ?? NSApp.mainWindow)?.center() }

    func fill() {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow,
              let screen = window.screen ?? NSScreen.main else { return }
        window.setFrame(screen.visibleFrame, display: true, animate: true)
    }

    func exportDiagnostics() { model?.requestDiagnosticsExport() }
    func repairCoreFeatures() { model?.repairCoreFeatures() }
    func showTutorials() { model?.showingTutorials = true }
}
