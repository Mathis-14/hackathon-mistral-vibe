//
//  MenuBarPanelManager.swift
//  leanring-buddy
//
//  Manages the NSStatusItem (menu bar icon) and a custom borderless NSPanel
//  that drops down below it when clicked. The panel hosts a SwiftUI view
//  (VibeBuddyPanelView) via NSHostingView. Uses the same NSPanel pattern as
//  FloatingSessionButton and GlobalPushToTalkOverlay for consistency.
//
//  The panel is non-activating so it does not steal focus from the user's
//  current app, and auto-dismisses when the user clicks outside.
//

import AppKit
import SwiftUI

extension Notification.Name {
    static let clickyDismissPanel = Notification.Name("clickyDismissPanel")
}

/// Custom NSPanel subclass that can become the key window even with
/// .nonactivatingPanel style, allowing text fields to receive focus.
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class MenuBarPanelManager: NSObject {
    private var statusItem: NSStatusItem?
    private var panel: NSPanel?
    private var clickOutsideMonitor: Any?
    private var dismissPanelObserver: NSObjectProtocol?

    private let companionManager: CompanionManager

    /// Owns the panel's chat transcript and the worker round-trip. Exposed
    /// so the push-to-talk transcript can be routed into the same pipeline
    /// as typed input (v1 wiring).
    let chatController = VibeBuddyChatController()

    /// Routines live as long as the panel manager: the scheduler keeps
    /// ticking (and posting native alerts) even while the panel is closed.
    let routineStore: RoutineStore
    let routineScheduler: RoutineScheduler
    private let panelWidth: CGFloat = VibeBuddyPanelView.preferredSize.width
    private let panelEdgeMargin: CGFloat = 12

    /// Side-panel height: the full visible screen height minus margins, so
    /// the panel hugs the right edge instead of covering the working area.
    private var panelHeight: CGFloat {
        let screen = NSScreen.main?.visibleFrame.height ?? VibeBuddyPanelView.preferredSize.height
        return screen - panelEdgeMargin * 2
    }

    init(companionManager: CompanionManager) {
        self.companionManager = companionManager
        let store = RoutineStore()
        self.routineStore = store
        self.routineScheduler = RoutineScheduler(store: store)
        super.init()
        createStatusItem()

        dismissPanelObserver = NotificationCenter.default.addObserver(
            forName: .clickyDismissPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hidePanel()
        }
    }

    deinit {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let observer = dismissPanelObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Status Item

    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem?.button else { return }

        // The Mistral M as a template image (white-on-transparent source):
        // macOS renders it black or white to match the menu bar, exactly
        // like the other assistants' icons.
        if let logoURL = Bundle.main.url(forResource: "menubar-mistral", withExtension: "png"),
           let logo = NSImage(contentsOf: logoURL) {
            logo.size = NSSize(width: 18, height: 18)
            logo.isTemplate = true
            button.image = logo
        } else {
            button.image = NSImage(systemSymbolName: "message.badge.waveform", accessibilityDescription: "Vibe Buddy")
            button.image?.isTemplate = true
        }
        button.action = #selector(statusItemClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// Right-click on the status item shows the standard app menu (Quit).
    private func showStatusItemMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Vibe Buddy", action: #selector(quitApp), keyEquivalent: "q")
            .target = self
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil // detach so left-click keeps toggling the panel
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    /// Opens the panel automatically on app launch so the user sees
    /// permissions and the start button right away.
    func showPanelOnLaunch() {
        // Small delay so the status item has time to appear in the menu bar
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.showPanel()
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusItemMenu()
        } else {
            togglePanel()
        }
    }

    /// Toggles the panel — same behavior as clicking the status item.
    /// Called by the global summon hotkey (fn+control).
    func togglePanel() {
        if let panel, panel.isVisible {
            hidePanel()
        } else {
            showPanel()
        }
    }

    // MARK: - Panel Lifecycle

    /// Shows (or re-fronts) the panel. Internal so the app delegate can
    /// surface it when a push-to-talk transcript arrives.
    func showPanel() {
        if panel == nil {
            createPanel()
        }
        guard let panel else { return }

        let finalFrame = sidePanelFrame()

        if panel.isVisible {
            panel.setFrame(finalFrame, display: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            // Slide in from the right edge: start fully offscreen, ease out
            // into the docked position.
            var startFrame = finalFrame
            startFrame.origin.x = (NSScreen.main?.frame.maxX ?? finalFrame.maxX) + 8
            panel.setFrame(startFrame, display: false)
            panel.alphaValue = 0.7
            panel.makeKeyAndOrderFront(nil)
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(finalFrame, display: true)
                panel.animator().alphaValue = 1
            }
        }
        installClickOutsideMonitor()
    }

    private func hidePanel() {
        removeClickOutsideMonitor()
        guard let panel, panel.isVisible else { return }

        // Slide back out to the right, then order out and reset for reuse.
        var offscreenFrame = panel.frame
        offscreenFrame.origin.x = (NSScreen.main?.frame.maxX ?? panel.frame.maxX) + 8
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(offscreenFrame, display: true)
            panel.animator().alphaValue = 0.7
        }, completionHandler: {
            panel.orderOut(nil)
            panel.alphaValue = 1
        })
    }

    private func createPanel() {
        let vibeBuddyPanelView = VibeBuddyPanelContainer(
            controller: chatController,
            routineStore: routineStore,
            routineScheduler: routineScheduler,
            permissionsSource: companionManager
        )

        let hostingView = NSHostingView(rootView: vibeBuddyPanelView)
        hostingView.frame = NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = .clear

        let menuBarPanel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        menuBarPanel.isFloatingPanel = true
        menuBarPanel.level = .floating
        menuBarPanel.isOpaque = false
        menuBarPanel.backgroundColor = .clear
        // Native window shadow hugs the rounded SwiftUI shape (the hosting
        // view is clear outside it), so the panel floats like a real popover.
        menuBarPanel.hasShadow = true
        menuBarPanel.hidesOnDeactivate = false
        menuBarPanel.isExcludedFromWindowsMenu = true
        menuBarPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        menuBarPanel.isMovableByWindowBackground = false
        menuBarPanel.titleVisibility = .hidden
        menuBarPanel.titlebarAppearsTransparent = true

        menuBarPanel.contentView = hostingView
        panel = menuBarPanel
    }

    /// The docked side-panel frame: pinned to the right edge of the main
    /// screen at full visible height.
    private func sidePanelFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: panelWidth, height: 560)
        }
        let visible = screen.visibleFrame
        return NSRect(
            x: visible.maxX - panelWidth - panelEdgeMargin,
            y: visible.minY + panelEdgeMargin,
            width: panelWidth,
            height: panelHeight
        )
    }

    // MARK: - Click Outside Dismissal

    /// Installs a global event monitor that hides the panel when the user clicks
    /// anywhere outside it — the same transient dismissal behavior as NSPopover.
    /// Uses a short delay so that system permission dialogs (triggered by Grant
    /// buttons in the panel) don't immediately dismiss the panel when they appear.
    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()

        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let panel = self.panel else { return }

            // Check if the click is inside the status item button — if so, the
            // statusItemClicked handler will toggle the panel, so don't also hide.
            let clickLocation = NSEvent.mouseLocation
            if panel.frame.contains(clickLocation) {
                return
            }

            // Delay dismissal slightly to avoid closing the panel when
            // a system permission dialog appears (e.g. microphone access).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                guard panel.isVisible else { return }

                // If permissions aren't all granted yet, a system dialog
                // may have focus — don't dismiss during onboarding.
                if !self.companionManager.allPermissionsGranted && !NSApp.isActive {
                    return
                }

                self.hidePanel()
            }
        }
    }

    private func removeClickOutsideMonitor() {
        if let monitor = clickOutsideMonitor {
            NSEvent.removeMonitor(monitor)
            clickOutsideMonitor = nil
        }
    }
}
