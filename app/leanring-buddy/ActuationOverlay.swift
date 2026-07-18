//
//  ActuationOverlay.swift
//  Vibe Buddy
//
//  The on-screen actuation trace (PRODUCT.md MUST #3/#6: the product never
//  acts invisibly). Every [OPEN_APP:] execution shows a large Mistral-styled
//  pill — app icon + "Opening Xcode…" — centered at the bottom of the screen
//  the user is working on: fade in, hold 2.2s, fade out.
//
//  The window is borderless, click-through, and non-activating (same
//  pattern as OverlayWindow.swift) so the trace never steals focus from
//  the app being opened.
//

import AppKit
import SwiftUI

@MainActor
final class ActuationOverlay {

    static let shared = ActuationOverlay()

    private var overlayWindow: ActuationOverlayWindow?
    private var pendingFadeOut: DispatchWorkItem?
    private var pendingRemoval: DispatchWorkItem?

    private static let fadeInDuration: TimeInterval = 0.25
    private static let holdDuration: TimeInterval = 2.2
    private static let fadeOutDuration: TimeInterval = 0.4

    private init() {}

    /// Shows the actuation trace pill for the given app name. Safe to call
    /// repeatedly — a new trace replaces the current one and restarts the
    /// fade-in → hold → fade-out cycle.
    func showTrace(appName: String) {
        pendingFadeOut?.cancel()
        pendingRemoval?.cancel()

        let screen = screenForTrace()
        let appIcon = ActuationExecutor.applicationURL(named: appName).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }

        let window = overlayWindow ?? ActuationOverlayWindow()
        overlayWindow = window

        let hostingView = NSHostingView(
            rootView: ActuationTracePillView(appName: appName, appIcon: appIcon)
        )
        let pillSize = hostingView.fittingSize
        hostingView.frame = NSRect(origin: .zero, size: pillSize)
        window.contentView = hostingView

        // Bottom-center of the target screen, floating a bit above the Dock.
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - pillSize.width / 2,
            y: visibleFrame.minY + 96
        )
        window.setFrame(NSRect(origin: origin, size: pillSize), display: true)

        // Fade in without activating the app.
        window.alphaValue = 0
        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeInDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            window.animator().alphaValue = 1
        }

        // Hold, then fade out and drop the window.
        let fadeOut = DispatchWorkItem { [weak self] in
            self?.fadeOutAndRemove()
        }
        pendingFadeOut = fadeOut
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.fadeInDuration + Self.holdDuration,
            execute: fadeOut
        )
    }

    private func fadeOutAndRemove() {
        guard let window = overlayWindow else { return }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
        }

        // Remove after the fade completes — via a cancellable work item so a
        // new showTrace() during the fade can reclaim the window instead.
        let removal = DispatchWorkItem { [weak self] in
            guard let self, let window = self.overlayWindow else { return }
            window.orderOut(nil)
            window.contentView = nil
            self.overlayWindow = nil
        }
        pendingRemoval = removal
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fadeOutDuration, execute: removal)
    }

    /// The screen the user is working on: the one under the mouse, falling
    /// back to the main screen.
    private func screenForTrace() -> NSScreen {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

// MARK: - Window

/// Borderless, click-through, non-activating window for the trace pill.
/// Mirrors OverlayWindow.swift: screen-saver level, joins all Spaces,
/// never becomes key or main.
private final class ActuationOverlayWindow: NSWindow {

    init() {
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hasShadow = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Pill View

/// The trace pill: app icon + "Opening <App>…" on a dark Mistral surface
/// with an orange glow so the action reads unmistakably on screen.
private struct ActuationTracePillView: View {
    let appName: String
    let appIcon: NSImage?

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            if let appIcon {
                Image(nsImage: appIcon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
            } else {
                Image(systemName: "arrow.up.forward.app.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundColor(DS.Colors.accentText)
                    .frame(width: 44, height: 44)
            }

            Text("Opening \(appName)…")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(DS.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Spacing.xxl)
        .padding(.vertical, DS.Spacing.md)
        .background(
            Capsule()
                .fill(DS.Colors.surface1.opacity(0.97))
        )
        .overlay(
            Capsule()
                .stroke(DS.Colors.accent.opacity(0.65), lineWidth: 1.5)
        )
        .shadow(color: DS.Colors.accent.opacity(0.35), radius: 22, x: 0, y: 0)
        .shadow(color: Color.black.opacity(0.45), radius: 16, x: 0, y: 6)
        // Breathing room so the glow shadows aren't clipped by the window bounds.
        .padding(28)
    }
}
