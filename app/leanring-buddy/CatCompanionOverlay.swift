//
//  CatCompanionOverlay.swift
//  Vibe Buddy
//
//  A tiny animated cat that patrols the bottom-right corner of the screen
//  whenever Vibe Buddy is working — listening to the mic, transcribing with
//  Voxtral, or waiting on Mistral. Click-through, non-activating, and it
//  fades away the moment the app goes idle. Pure delight, zero interference.
//
//  Asset: cat.gif (from the team's landing assets), animated by AppKit's
//  native GIF playback (NSImageView.animates).
//

import AppKit

@MainActor
final class CatCompanionOverlay {
    static let shared = CatCompanionOverlay()

    private var panel: NSPanel?
    private var catImageView: NSImageView?
    private var statusLabel: NSTextField?
    private var bubbleContainer: NSView?
    private var walkTimer: Timer?
    private var walkDirection: CGFloat = 1
    private var isVisible = false

    private let panelSize = NSSize(width: 320, height: 120)
    private let catSize = NSSize(width: 72, height: 63)

    func show(_ status: String) {
        createPanelIfNeeded()
        statusLabel?.stringValue = status
        layoutBubble()

        guard let panel else { return }
        if !isVisible {
            isVisible = true
            positionAtBottomRight()
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
            startWalking()
        }
    }

    func hide() {
        guard isVisible, let panel else { return }
        isVisible = false
        walkTimer?.invalidate()
        walkTimer = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: {
            if !self.isVisible {
                panel.orderOut(nil)
            }
        })
    }

    // MARK: - Setup

    private func createPanelIfNeeded() {
        guard panel == nil else { return }

        let overlayPanel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        overlayPanel.isOpaque = false
        overlayPanel.backgroundColor = .clear
        overlayPanel.hasShadow = false
        overlayPanel.level = .statusBar
        overlayPanel.ignoresMouseEvents = true
        overlayPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        overlayPanel.isExcludedFromWindowsMenu = true

        let container = NSView(frame: NSRect(origin: .zero, size: panelSize))

        let imageView = NSImageView(frame: NSRect(x: 0, y: 0, width: catSize.width, height: catSize.height))
        if let catURL = Bundle.main.url(forResource: "cat", withExtension: "gif"),
           let catImage = NSImage(contentsOf: catURL) {
            imageView.image = catImage
        }
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        container.addSubview(imageView)

        let bubble = NSView(frame: .zero)
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.10, blue: 0.10, alpha: 0.92).cgColor
        bubble.layer?.cornerRadius = 9
        bubble.layer?.borderWidth = 1
        bubble.layer?.borderColor = NSColor(calibratedRed: 1.0, green: 0.44, blue: 0.0, alpha: 0.55).cgColor

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = NSColor(calibratedWhite: 0.93, alpha: 1)
        bubble.addSubview(label)
        container.addSubview(bubble)

        overlayPanel.contentView = container
        panel = overlayPanel
        catImageView = imageView
        statusLabel = label
        bubbleContainer = bubble
    }

    private func positionAtBottomRight() {
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(
            x: frame.maxX - panelSize.width - 24,
            y: frame.minY + 8
        ))
    }

    // MARK: - Walk cycle

    private func startWalking() {
        walkTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stepWalk() }
        }
        RunLoop.main.add(timer, forMode: .common)
        walkTimer = timer
    }

    private func stepWalk() {
        guard let catImageView else { return }
        var origin = catImageView.frame.origin
        origin.x += 1.6 * walkDirection

        let maxX = panelSize.width - catSize.width
        if origin.x <= 0 {
            origin.x = 0
            walkDirection = 1
        } else if origin.x >= maxX {
            origin.x = maxX
            walkDirection = -1
        }
        catImageView.setFrameOrigin(origin)

        // The gif faces left by default; mirror it when patrolling rightwards.
        catImageView.layer?.setAffineTransform(
            walkDirection > 0
                ? CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -catSize.width, y: 0)
                : .identity
        )
        layoutBubble()
    }

    private func layoutBubble() {
        guard let bubbleContainer, let statusLabel, let catImageView else { return }
        statusLabel.sizeToFit()
        let labelSize = statusLabel.frame.size
        let bubbleSize = NSSize(width: labelSize.width + 18, height: labelSize.height + 10)
        let catCenterX = catImageView.frame.midX
        var bubbleX = catCenterX - bubbleSize.width / 2
        bubbleX = max(0, min(bubbleX, panelSize.width - bubbleSize.width))
        bubbleContainer.frame = NSRect(
            x: bubbleX,
            y: catSize.height + 6,
            width: bubbleSize.width,
            height: bubbleSize.height
        )
        statusLabel.frame.origin = NSPoint(x: 9, y: 5)
    }
}
