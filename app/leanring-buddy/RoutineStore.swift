//
//  RoutineStore.swift
//  Vibe Buddy
//
//  Scheduled routines model + persistence (PRODUCT.md MUST #4).
//  Routines are stored as a JSON blob in UserDefaults under
//  "vibebuddy.routines" — no DB, per AGENTS.md stack decision.
//
//  Seeding: exactly once, on first launch (i.e. when the defaults key has
//  never been written). After that the persisted array — even an empty
//  one — is the truth, so deleting the seed never resurrects it.
//

import Combine
import Foundation

// MARK: - Routine

/// One user-defined scheduled routine: a prompt run every `intervalMinutes`,
/// whose latest result (`lastArtifact`) is kept for display in the panel.
struct Routine: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var prompt: String
    var intervalMinutes: Int
    var isEnabled: Bool
    var lastRunAt: Date?
    var lastArtifact: String?

    init(
        id: UUID = UUID(),
        name: String,
        prompt: String,
        intervalMinutes: Int,
        isEnabled: Bool = false,
        lastRunAt: Date? = nil,
        lastArtifact: String? = nil
    ) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.intervalMinutes = intervalMinutes
        self.isEnabled = isEnabled
        self.lastRunAt = lastRunAt
        self.lastArtifact = lastArtifact
    }

    /// True when the scheduler should fire this routine at `now`: enabled
    /// and either never run or last run at least `intervalMinutes` ago.
    func isDue(at now: Date) -> Bool {
        guard isEnabled else { return false }
        guard let lastRunAt else { return true }
        return now.timeIntervalSince(lastRunAt) >= TimeInterval(intervalMinutes) * 60
    }
}

// MARK: - Store

/// Owns the routine list, persists every mutation to UserDefaults as JSON,
/// and seeds one realistic example on the very first launch only.
@MainActor
final class RoutineStore: ObservableObject {

    /// UserDefaults key holding the JSON-encoded `[Routine]`.
    static let defaultsKey = "vibebuddy.routines"

    @Published private(set) var routines: [Routine]

    private let defaults: UserDefaults

    /// Number of currently enabled routines — drives `RoutinesBadge`.
    var enabledCount: Int {
        routines.lazy.filter(\.isEnabled).count
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Self.defaultsKey) {
            // The key exists → not a first launch. A corrupt payload decodes
            // to an empty list rather than re-seeding over user data.
            self.routines = (try? JSONDecoder().decode([Routine].self, from: data)) ?? []
        } else {
            // First launch only: seed one realistic, disabled example.
            self.routines = [Self.makeSeedRoutine()]
            persist()
        }
    }

    // MARK: Mutations (every one persists)

    @discardableResult
    func add(name: String, prompt: String, intervalMinutes: Int) -> Routine {
        let routine = Routine(name: name, prompt: prompt, intervalMinutes: intervalMinutes)
        routines.append(routine)
        persist()
        return routine
    }

    /// Replaces the stored routine carrying `routine.id`; no-op if it was deleted.
    func update(_ routine: Routine) {
        guard let index = routines.firstIndex(where: { $0.id == routine.id }) else { return }
        routines[index] = routine
        persist()
    }

    func remove(_ id: UUID) {
        routines.removeAll { $0.id == id }
        persist()
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].isEnabled = isEnabled
        persist()
    }

    /// Called by the scheduler when a run finishes: stores the artifact and
    /// stamps `lastRunAt`. No-op if the routine was deleted mid-run.
    func recordRun(id: UUID, artifact: String, at date: Date = Date()) {
        guard let index = routines.firstIndex(where: { $0.id == id }) else { return }
        routines[index].lastRunAt = date
        routines[index].lastArtifact = artifact
        persist()
    }

    func routine(withID id: UUID) -> Routine? {
        routines.first { $0.id == id }
    }

    /// Wholesale replacement — used by previews and tests to stage content.
    func replaceAll(_ routines: [Routine]) {
        self.routines = routines
        persist()
    }

    // MARK: Persistence

    private func persist() {
        guard let data = try? JSONEncoder().encode(routines) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    // MARK: Seed

    /// The single first-launch example. Disabled by default — nothing fires
    /// until the user opts in (PRODUCT.md MUST #6: no unattended action the
    /// user hasn't scheduled).
    static func makeSeedRoutine() -> Routine {
        Routine(
            name: "Morning brief",
            prompt: """
                Give me a short brief to start my day: today's calendar highlights, \
                the weather in Paris, and the top three tech headlines I should know \
                about. Keep it under 120 words, plain text, most important first.
                """,
            intervalMinutes: 60,
            isEnabled: false
        )
    }

    // MARK: Preview support

    /// A store backed by a throwaway UserDefaults suite, pre-filled with
    /// `routines` — for SwiftUI previews only.
    static func previewStore(routines: [Routine]) -> RoutineStore {
        let suiteName = "vibebuddy.preview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        let store = RoutineStore(defaults: defaults)
        store.replaceAll(routines)
        return store
    }
}
