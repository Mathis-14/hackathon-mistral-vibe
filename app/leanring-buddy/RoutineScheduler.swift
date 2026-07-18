//
//  RoutineScheduler.swift
//  Vibe Buddy
//
//  Fires enabled routines when they come due (one 30-second tick timer),
//  runs their prompt through the same worker/replay chat path as the panel
//  (silently — no UI), stores the artifact on the routine, and surfaces the
//  result as a native macOS alert (PRODUCT.md MUST #4).
//
//  The alert IS the on-screen trace (PRODUCT.md MUST #6): a routine only
//  runs because the user scheduled it, and every finished run lands as a
//  visible notification.
//
//  On stage the alert is triggered manually via `runNow(_:)` — a cron can't
//  fire on cue, so the demo never live-schedules (PRODUCT.md).
//

import Combine
import Foundation
import UserNotifications

@MainActor
final class RoutineScheduler: NSObject, ObservableObject, UNUserNotificationCenterDelegate {

    /// IDs of routines currently mid-run — drives the "Running…" state in
    /// RoutinesView and guards against overlapping runs of the same routine.
    @Published private(set) var runningRoutineIDs: Set<UUID> = []

    /// The single tick cadence. Due-ness itself is per-routine
    /// (`Routine.isDue(at:)`), the timer just polls.
    static let tickInterval: TimeInterval = 30

    private let store: RoutineStore
    private var tickTimer: Timer?
    private var hasRequestedNotificationAuthorization = false

    init(store: RoutineStore, startsAutomatically: Bool = true) {
        self.store = store
        super.init()
        if startsAutomatically {
            start()
        }
    }

    // MARK: Lifecycle

    /// Starts the 30 s tick. Idempotent.
    func start() {
        guard tickTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.tickInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
        timer.tolerance = 5
        tickTimer = timer
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
    }

    // MARK: Firing

    /// Demo/manual entry point: fires the exact same path as the scheduled
    /// tick, immediately. Used by the "Run now" button in RoutinesView.
    func runNow(_ routine: Routine) {
        run(routine)
    }

    func isRunning(_ routine: Routine) -> Bool {
        runningRoutineIDs.contains(routine.id)
    }

    private func tick(now: Date = Date()) {
        for routine in store.routines
        where routine.isDue(at: now) && !runningRoutineIDs.contains(routine.id) {
            run(routine)
        }
    }

    private func run(_ routine: Routine) {
        guard !runningRoutineIDs.contains(routine.id) else { return }
        runningRoutineIDs.insert(routine.id)

        Task { [weak self] in
            do {
                // Same chat path as the panel: live worker when reachable,
                // built-in replay fixture otherwise. The deltas accumulate
                // silently — the returned result carries the full text.
                let result = try await WorkerChatReplay.streamReply(
                    messages: [(role: "user", content: routine.prompt)],
                    onDelta: { _ in }
                )
                self?.finishRun(routine, artifact: result.text, succeeded: true)
            } catch {
                // Still stamp lastRunAt so a broken routine waits a full
                // interval instead of retrying every 30 s tick.
                self?.finishRun(
                    routine,
                    artifact: "Run failed: \(error.localizedDescription)",
                    succeeded: false
                )
            }
        }
    }

    private func finishRun(_ routine: Routine, artifact: String, succeeded: Bool) {
        runningRoutineIDs.remove(routine.id)
        store.recordRun(id: routine.id, artifact: artifact)
        postNotification(
            title: succeeded ? "Routine finished: \(routine.name)" : "Routine failed: \(routine.name)",
            body: Self.firstLine(of: artifact)
        )
    }

    // MARK: Native alert

    private func postNotification(title: String, body: String) {
        let center = UNUserNotificationCenter.current()

        // Present banners even while Vibe Buddy is frontmost (macOS hides
        // foreground-app notifications unless the delegate opts in) — on
        // stage "Run now" is clicked with the panel open.
        center.delegate = self

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "vibebuddy.routine.\(UUID().uuidString)",
            content: content,
            trigger: nil // deliver immediately
        )

        if hasRequestedNotificationAuthorization {
            center.add(request) { error in
                if let error {
                    NSLog("VibeBuddy routine notification failed: \(error.localizedDescription)")
                }
            }
        } else {
            // Lazy one-time authorization request; the alert is queued from
            // its completion so the very first run isn't lost to the race.
            hasRequestedNotificationAuthorization = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in
                center.add(request) { error in
                    if let error {
                        NSLog("VibeBuddy routine notification failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// The alert body: the first non-empty line of the artifact. Pure —
    /// nonisolated so tests and helpers can call it from anywhere.
    nonisolated static func firstLine(of artifact: String) -> String {
        artifact
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? "Artifact ready in the panel."
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
