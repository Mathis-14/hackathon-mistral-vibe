//
//  VibeSessionWatcher.swift
//  Vibe Buddy
//
//  Read-only watcher over the local Mistral Vibe Code CLI session logs
//  (~/.vibe/logs/session/<dir>/meta.json). Surfaces terminal coding-agent
//  sessions in the panel — the bridge between Vibe Buddy and the Vibe Code
//  lineup (decision D012). Never writes anything.
//
//  meta.json contract (verified live on vibe 2.21.0, see the spike notes):
//    session_id, start_time, end_time (null/absent while running), title,
//    environment.working_directory, stats.{session_prompt_tokens,
//    session_completion_tokens, input_price_per_million, output_price_per_million}
//

import Combine
import Foundation

struct VibeSession: Identifiable, Equatable {
    /// Session directory name, e.g. "session_20260718_094422_7098a039".
    let id: String
    var title: String
    var workingDirectory: String
    var isActive: Bool
    var costUsd: Double
    var startedAt: Date
    var endedAt: Date?

    var projectName: String {
        URL(fileURLWithPath: workingDirectory).lastPathComponent
    }
}

@MainActor
final class VibeSessionWatcher: ObservableObject {
    /// Active sessions first (newest start first), then recently finished
    /// ones, capped for the panel strip.
    @Published private(set) var sessions: [VibeSession] = []

    /// Finished sessions older than this are not worth showing.
    private let recentWindow: TimeInterval = 30 * 60
    private let maxSessions = 4
    private var timer: Timer?

    private let sessionsDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".vibe/logs/session", isDirectory: true)

    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func start() {
        guard timer == nil else { return }
        refresh()
        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        let fileManager = FileManager.default
        guard let entries = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            if !sessions.isEmpty { sessions = [] }
            return
        }

        // Newest directories first; parsing more than ~40 would be wasted work.
        let candidates = entries
            .sorted { modificationDate(of: $0) > modificationDate(of: $1) }
            .prefix(40)

        let now = Date()
        var parsed: [VibeSession] = []
        for directory in candidates {
            guard let session = parseSession(at: directory) else { continue }
            let isRecent = session.isActive
                || (session.endedAt.map { now.timeIntervalSince($0) < recentWindow } ?? false)
            if isRecent {
                parsed.append(session)
            }
        }

        parsed.sort { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.startedAt > rhs.startedAt
        }
        let capped = Array(parsed.prefix(maxSessions))
        if capped != sessions {
            sessions = capped
        }
    }

    private func parseSession(at directory: URL) -> VibeSession? {
        let metaURL = directory.appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: metaURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let stats = json["stats"] as? [String: Any] ?? [:]
        let promptTokens = (stats["session_prompt_tokens"] as? Double) ?? 0
        let completionTokens = (stats["session_completion_tokens"] as? Double) ?? 0
        let inputPrice = (stats["input_price_per_million"] as? Double) ?? 0
        let outputPrice = (stats["output_price_per_million"] as? Double) ?? 0
        let costUsd = (promptTokens * inputPrice + completionTokens * outputPrice) / 1_000_000

        let environment = json["environment"] as? [String: Any] ?? [:]
        let endTimeString = json["end_time"] as? String

        return VibeSession(
            id: directory.lastPathComponent,
            title: (json["title"] as? String) ?? "Vibe session",
            workingDirectory: (environment["working_directory"] as? String) ?? "",
            isActive: endTimeString == nil,
            costUsd: costUsd,
            startedAt: (json["start_time"] as? String).flatMap(Self.parseDate) ?? modificationDate(of: directory),
            endedAt: endTimeString.flatMap(Self.parseDate)
        )
    }

    private static func parseDate(_ string: String) -> Date? {
        isoParser.date(from: string)
            ?? ISO8601DateFormatter().date(from: string)
    }

    private func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}
