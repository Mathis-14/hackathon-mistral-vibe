//
//  GlobalSummonHotkeyMonitor.swift
//  leanring-buddy
//
//  Global summon hotkey for Vibe Buddy: a listen-only CGEvent tap on
//  flagsChanged that fires exactly once when the fn+control chord becomes
//  active (decision D003). If the tap cannot be created, it falls back to
//  the ctrl+option chord via the same tap logic and keeps retrying the
//  installation so the hotkey comes alive as soon as the Accessibility
//  permission is granted.
//
//  Mirrors GlobalPushToTalkShortcutMonitor's tap conventions: listen-only
//  (never consumes or delays events, so both taps coexist), installed on the
//  main run loop, re-enabled on kCGEventTapDisabledByTimeout.
//

import AppKit
import CoreGraphics
import Foundation

final class GlobalSummonHotkeyMonitor {
    /// Which modifier chord summons the panel (decision D003).
    enum SummonChord {
        case fnControl
        case controlOption

        var displayName: String {
            switch self {
            case .fnControl:
                return "fn+control"
            case .controlOption:
                return "ctrl+option (fallback)"
            }
        }

        fileprivate var requiredFlags: CGEventFlags {
            switch self {
            case .fnControl:
                return [.maskSecondaryFn, .maskControl]
            case .controlOption:
                return [.maskControl, .maskAlternate]
            }
        }
    }

    /// Fires exactly once per chord press, on the transition INTO the chord
    /// (never on release or while extra modifiers join the chord). Invoked on
    /// the main thread — the tap callback runs on the main run loop.
    var onSummonChordActivated: (() -> Void)?

    private(set) var activeChord: SummonChord = .fnControl

    private var globalEventTap: CFMachPort?
    private var globalEventTapRunLoopSource: CFRunLoopSource?
    private var tapInstallRetryTimer: Timer?
    private var hasPromptedForAccessibilityPermission = false
    /// Mutated exclusively from the CGEvent tap callback, which runs on
    /// `CFRunLoopGetMain()` and therefore always executes on the main thread.
    private var wasSummonChordPreviouslyActive = false

    deinit {
        stop()
    }

    func start() {
        // Already installed — nothing to do (mirrors the push-to-talk monitor,
        // which is start()-ed repeatedly by the permission poller).
        guard globalEventTap == nil else { return }

        if !AXIsProcessTrusted() && !hasPromptedForAccessibilityPermission {
            hasPromptedForAccessibilityPermission = true
            let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(promptOptions)
            print("⚠️ Summon hotkey: Accessibility permission not granted yet — system prompt requested")
        }

        installEventTap()
    }

    func stop() {
        wasSummonChordPreviouslyActive = false

        tapInstallRetryTimer?.invalidate()
        tapInstallRetryTimer = nil

        if let globalEventTapRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
            self.globalEventTapRunLoopSource = nil
        }

        if let globalEventTap {
            CFMachPortInvalidate(globalEventTap)
            self.globalEventTap = nil
        }
    }

    // MARK: - Tap Installation

    private func installEventTap() {
        let eventMask = CGEventMask(1) << CGEventType.flagsChanged.rawValue

        let eventTapCallback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else {
                return Unmanaged.passUnretained(event)
            }

            let globalSummonHotkeyMonitor = Unmanaged<GlobalSummonHotkeyMonitor>
                .fromOpaque(userInfo)
                .takeUnretainedValue()

            return globalSummonHotkeyMonitor.handleGlobalEventTap(
                eventType: eventType,
                event: event
            )
        }

        guard let globalEventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            // D003: the fn+control tap couldn't be created — pivot to the
            // scaffold-proven ctrl+option chord (same tap logic) and keep
            // retrying so the hotkey installs the moment Accessibility lands.
            if activeChord == .fnControl {
                activeChord = .controlOption
                print("⚠️ Summon hotkey: couldn't create CGEvent tap for fn+control — falling back to ctrl+option (D003)")
            } else {
                print("⚠️ Summon hotkey: couldn't create CGEvent tap (Accessibility permission missing?) — will retry")
            }
            scheduleTapInstallRetry()
            return
        }

        guard let globalEventTapRunLoopSource = CFMachPortCreateRunLoopSource(
            kCFAllocatorDefault,
            globalEventTap,
            0
        ) else {
            CFMachPortInvalidate(globalEventTap)
            print("⚠️ Summon hotkey: couldn't create event tap run loop source — will retry")
            scheduleTapInstallRetry()
            return
        }

        self.globalEventTap = globalEventTap
        self.globalEventTapRunLoopSource = globalEventTapRunLoopSource

        CFRunLoopAddSource(CFRunLoopGetMain(), globalEventTapRunLoopSource, .commonModes)
        CGEvent.tapEnable(tap: globalEventTap, enable: true)

        tapInstallRetryTimer?.invalidate()
        tapInstallRetryTimer = nil

        print("🔥 Summon hotkey ACTIVE: \(activeChord.displayName) — listen-only tap installed")
    }

    /// Retries the tap installation every few seconds until it succeeds —
    /// covers the "user grants Accessibility after launch" path without
    /// requiring a relaunch.
    private func scheduleTapInstallRetry() {
        guard tapInstallRetryTimer == nil else { return }

        tapInstallRetryTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.globalEventTap == nil else { return }
            self.installEventTap()
        }
    }

    // MARK: - Event Handling

    private func handleGlobalEventTap(
        eventType: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
            if let globalEventTap {
                CGEvent.tapEnable(tap: globalEventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard eventType == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let isSummonChordActiveNow = event.flags.contains(activeChord.requiredFlags)

        // Fire only on the transition INTO the chord — never on release,
        // and never again while the chord stays held as flags keep changing.
        if isSummonChordActiveNow && !wasSummonChordPreviouslyActive {
            onSummonChordActivated?()
        }
        wasSummonChordPreviouslyActive = isSummonChordActiveNow

        return Unmanaged.passUnretained(event)
    }
}
