import AppKit
import Foundation
import SwiftUI
#if SWIFT_PACKAGE
import MacGameToolboxCore
#endif

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    static let shared = StatusBarController()

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private weak var model: AppModel?

    private override init() {
        super.init()
    }

    func setup(model: AppModel) {
        self.model = model
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "gamecontroller.fill", accessibilityDescription: "MetalPilot")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        let hostingController = NSHostingController(
            rootView: MenuBarPopoverView().environmentObject(model)
        )
        let popoverSize = NSSize(width: 380, height: 500)
        hostingController.preferredContentSize = popoverSize
        p.contentSize = popoverSize
        p.contentViewController = hostingController
        self.popover = p
        self.statusItem = item
    }

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let popover = popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }
}
