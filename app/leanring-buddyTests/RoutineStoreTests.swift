//
//  RoutineStoreTests.swift
//  Unit tests for RoutineStore: first-launch seed-once semantics and the
//  UserDefaults JSON persistence round-trip.
//

import XCTest
@testable import VibeBuddy

final class RoutineStoreTests: XCTestCase {

    /// Each test gets its own throwaway suite so tests never touch the real
    /// app defaults nor each other.
    private func makeCleanDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "vibebuddy.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    // MARK: Seeding

    @MainActor
    func testFirstLaunchSeedsSingleDisabledMorningBrief() throws {
        let (defaults, suiteName) = makeCleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RoutineStore(defaults: defaults)

        XCTAssertEqual(store.routines.count, 1)
        let seed = try XCTUnwrap(store.routines.first)
        XCTAssertEqual(seed.name, "Morning brief")
        XCTAssertEqual(seed.intervalMinutes, 60)
        XCTAssertFalse(seed.isEnabled, "The seed must never fire unattended")
        XCTAssertNil(seed.lastRunAt)
        XCTAssertNil(seed.lastArtifact)
        XCTAssertFalse(seed.prompt.isEmpty)

        XCTAssertNotNil(
            defaults.data(forKey: RoutineStore.defaultsKey),
            "Seeding must persist immediately so the next launch is not a 'first launch'"
        )
    }

    @MainActor
    func testSeedHappensOnFirstLaunchOnly() {
        let (defaults, suiteName) = makeCleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstLaunch = RoutineStore(defaults: defaults)
        XCTAssertEqual(firstLaunch.routines.count, 1)

        // The user deletes the seed…
        firstLaunch.remove(firstLaunch.routines[0].id)
        XCTAssertTrue(firstLaunch.routines.isEmpty)

        // …and a relaunch must NOT resurrect it.
        let secondLaunch = RoutineStore(defaults: defaults)
        XCTAssertTrue(
            secondLaunch.routines.isEmpty,
            "An empty persisted list is user intent, not a first launch"
        )
    }

    // MARK: Persistence round-trip

    @MainActor
    func testPersistenceRoundTrip() throws {
        let (defaults, suiteName) = makeCleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RoutineStore(defaults: defaults)
        let added = store.add(
            name: "Standup notes",
            prompt: "Summarize yesterday's commits into three standup bullets.",
            intervalMinutes: 30
        )
        store.setEnabled(true, for: added.id)

        // A whole-second date keeps the JSON Double encoding lossless.
        let runDate = Date(timeIntervalSinceReferenceDate: 795_000_000)
        store.recordRun(id: added.id, artifact: "Line one\nLine two", at: runDate)

        let reloaded = RoutineStore(defaults: defaults)

        XCTAssertEqual(reloaded.routines, store.routines, "Full array must survive a relaunch")

        let roundTripped = try XCTUnwrap(reloaded.routine(withID: added.id))
        XCTAssertEqual(roundTripped.name, "Standup notes")
        XCTAssertEqual(roundTripped.prompt, "Summarize yesterday's commits into three standup bullets.")
        XCTAssertEqual(roundTripped.intervalMinutes, 30)
        XCTAssertTrue(roundTripped.isEnabled)
        XCTAssertEqual(roundTripped.lastRunAt, runDate)
        XCTAssertEqual(roundTripped.lastArtifact, "Line one\nLine two")
    }

    @MainActor
    func testMutationsOnMissingIDsAreNoOps() {
        let (defaults, suiteName) = makeCleanDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RoutineStore(defaults: defaults)
        let before = store.routines

        store.setEnabled(true, for: UUID())
        store.recordRun(id: UUID(), artifact: "orphan artifact")
        store.remove(UUID())

        XCTAssertEqual(store.routines, before)
    }

    // MARK: Due-ness (drives the scheduler tick)

    func testIsDueLogic() {
        let now = Date()

        let disabled = Routine(name: "r", prompt: "p", intervalMinutes: 1, isEnabled: false)
        XCTAssertFalse(disabled.isDue(at: now), "Disabled routines are never due")

        let neverRan = Routine(name: "r", prompt: "p", intervalMinutes: 60, isEnabled: true)
        XCTAssertTrue(neverRan.isDue(at: now), "Enabled + never run = due immediately")

        let justRan = Routine(
            name: "r", prompt: "p", intervalMinutes: 60, isEnabled: true,
            lastRunAt: now.addingTimeInterval(-120)
        )
        XCTAssertFalse(justRan.isDue(at: now))

        let overdue = Routine(
            name: "r", prompt: "p", intervalMinutes: 60, isEnabled: true,
            lastRunAt: now.addingTimeInterval(-3600)
        )
        XCTAssertTrue(overdue.isDue(at: now))
    }

    // MARK: Alert body helper

    func testFirstLineOfArtifactSkipsBlankLines() {
        XCTAssertEqual(
            RoutineScheduler.firstLine(of: "\n\n  \nGood morning!\nSecond line"),
            "Good morning!"
        )
        XCTAssertEqual(
            RoutineScheduler.firstLine(of: "   \n\n"),
            "Artifact ready in the panel."
        )
    }
}
