//
//  leanring_buddyApp.swift
//  leanring-buddy
//
//  Menu bar-only companion app. No dock icon, no main window — just an
//  always-available status item in the macOS menu bar. Clicking the icon
//  opens a floating panel with companion voice controls.
//

import Combine
import ServiceManagement
import SwiftUI
import Sparkle

@main
struct leanring_buddyApp: App {
    @NSApplicationDelegateAdaptor(CompanionAppDelegate.self) var appDelegate

    var body: some Scene {
        // The app lives entirely in the menu bar panel managed by the AppDelegate.
        // This empty Settings scene satisfies SwiftUI's requirement for at least
        // one scene but is never shown (LSUIElement=true removes the app menu).
        Settings {
            EmptyView()
        }
    }
}

/// Manages the companion lifecycle: creates the menu bar panel and starts
/// the companion voice pipeline on launch.
@MainActor
final class CompanionAppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarPanelManager: MenuBarPanelManager?
    private var globalSummonHotkeyMonitor: GlobalSummonHotkeyMonitor?
    private let wakeWordSidecarMonitor = WakeWordSidecarMonitor()
    private let companionManager = CompanionManager()
    private var catOverlayCancellable: AnyCancellable?
    private var sparkleUpdaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard: launching a second copy (Xcode + the
        // ~/Applications build, typically) just fronts the first one.
        // Skipped under XCTest: the test host must boot while the real app
        // is running, or every test run aborts with an early exit.
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let runningCopies = isRunningTests ? [] : NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.vibebuddy.app"
        )
        if runningCopies.count > 1 {
            print("🎯 Vibe Buddy: another instance is already running — quitting this one")
            runningCopies.first { $0 != NSRunningApplication.current }?
                .activate(options: [])
            NSApp.terminate(nil)
            return
        }

        print("🎯 Clicky: Starting...")
        print("🎯 Clicky: Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")")

        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 0])

        ClickyAnalytics.configure()
        ClickyAnalytics.trackAppOpened()

        menuBarPanelManager = MenuBarPanelManager(companionManager: companionManager)

        // Push-to-talk lands in the same pipeline as typed input: the final
        // transcript opens the panel and submits through the chat controller,
        // so the exchange is always visible on screen (PRODUCT.md MUST #6).
        companionManager.onTranscriptReady = { [weak self] transcript in
            let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            // Empty transcript = a wake capture that heard nothing — drop it.
            guard !trimmed.isEmpty, let panelManager = self?.menuBarPanelManager else { return }
            panelManager.showPanel()
            panelManager.chatController.submit(trimmed)
        }
        print("🎙️ Vibe Buddy: transcript hook installed — push-to-talk routes into the chat panel")

        // Global summon hotkey (fn+control, ctrl+option fallback — D003):
        // toggles the panel from anywhere in macOS.
        let summonHotkeyMonitor = GlobalSummonHotkeyMonitor()
        summonHotkeyMonitor.onSummonChordActivated = { [weak self] in
            self?.menuBarPanelManager?.togglePanel()
        }
        summonHotkeyMonitor.start()
        globalSummonHotkeyMonitor = summonHotkeyMonitor

        // « Hey Vibe » wake word (v2 stretch): optional Python sidecar; the
        // app works fully without it. Summons the panel like the hotkey.
        wakeWordSidecarMonitor.onWake = { [weak self] in
            guard let self else { return }
            // « Hey Vibe, … » — the panel slides in AND the mic opens: what
            // you say next is the command (silence closes the window).
            self.menuBarPanelManager?.showPanel()
            self.companionManager.beginWakeTriggeredCapture()
        }
        wakeWordSidecarMonitor.startIfAvailable()

        // The cat companion patrols the screen corner whenever the app is
        // actually doing something: mic open, Voxtral transcribing, or a
        // Mistral reply streaming. Visible feedback for every voice command.
        if let chatController = menuBarPanelManager?.chatController {
            catOverlayCancellable = companionManager.$voiceState
                .combineLatest(chatController.$isStreaming)
                .receive(on: DispatchQueue.main)
                .sink { voiceState, isStreaming in
                    switch (voiceState, isStreaming) {
                    case (.listening, _):
                        CatCompanionOverlay.shared.show("Listening…")
                    case (.processing, _):
                        CatCompanionOverlay.shared.show("Transcribing with Voxtral…")
                    case (_, true):
                        CatCompanionOverlay.shared.show("Thinking…")
                    default:
                        CatCompanionOverlay.shared.hide()
                    }
                }
        }

        companionManager.start()
        // Auto-open the panel if the user still needs to do something:
        // either they haven't onboarded yet, or permissions were revoked.
        if !companionManager.hasCompletedOnboarding || !companionManager.allPermissionsGranted {
            menuBarPanelManager?.showPanelOnLaunch()
        }
        registerAsLoginItemIfNeeded()
        // startSparkleUpdater()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wakeWordSidecarMonitor.stop()
        companionManager.stop()
    }

    /// Registers the app as a login item so it launches automatically on
    /// startup. Uses SMAppService which shows the app in System Settings >
    /// General > Login Items, letting the user toggle it off if they want.
    private func registerAsLoginItemIfNeeded() {
        let loginItemService = SMAppService.mainApp
        if loginItemService.status != .enabled {
            do {
                try loginItemService.register()
                print("🎯 Clicky: Registered as login item")
            } catch {
                print("⚠️ Clicky: Failed to register as login item: \(error)")
            }
        }
    }

    private func startSparkleUpdater() {
        let updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.sparkleUpdaterController = updaterController

        do {
            try updaterController.updater.start()
        } catch {
            print("⚠️ Clicky: Sparkle updater failed to start: \(error)")
        }
    }
}
