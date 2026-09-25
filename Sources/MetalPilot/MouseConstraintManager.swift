import Foundation
import AppKit
import CoreGraphics

@MainActor
public final class MouseConstraintManager {
    public static let shared = MouseConstraintManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isEnabled = false
    private var targetWindowFrame: CGRect = .zero

    private init() {}

    public func configure(targetFrame: CGRect) {
        self.targetWindowFrame = targetFrame
    }

    public func enable() {
        guard !isEnabled else { return }
        isEnabled = true
        CGDisplayHideCursor(CGMainDisplayID())
    }

    public func disable() {
        guard isEnabled else { return }
        isEnabled = false
        CGDisplayShowCursor(CGMainDisplayID())
    }

    public func toggle() -> Bool {
        if isEnabled {
            disable()
            return false
        } else {
            enable()
            return true
        }
    }
}
