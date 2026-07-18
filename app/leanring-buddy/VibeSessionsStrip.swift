//
//  VibeSessionsStrip.swift
//  Vibe Buddy
//
//  Compact panel section showing local Mistral Vibe Code CLI sessions
//  (read-only, fed by VibeSessionWatcher), grouped by project so agents
//  working the same repo read as one team. Hidden entirely when there is
//  nothing recent — the panel stays clean for non-Vibe-Code users.
//

import AppKit
import SwiftUI

struct VibeSessionsStrip: View {
    let sessions: [VibeSession]
    /// Called when a session row is clicked — the container opens the
    /// transcript inspector. Defaulted so existing call sites compile.
    var onSelect: (VibeSession) -> Void = { _ in }

    /// Projects the user collapsed this app run; everything starts expanded.
    @State private var collapsedProjects: Set<String> = []

    private var groupedSessions: [(project: String, sessions: [VibeSession])] {
        var order: [String] = []
        var buckets: [String: [VibeSession]] = [:]
        for session in sessions {
            if buckets[session.projectName] == nil { order.append(session.projectName) }
            buckets[session.projectName, default: []].append(session)
        }
        return order.map { (project: $0, sessions: buckets[$0] ?? []) }
    }

    var body: some View {
        if sessions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("VIBE CODE SESSIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(DS.Colors.textTertiary)

                let groups = groupedSessions
                ForEach(groups, id: \.project) { group in
                    // A single project needs no expander chrome.
                    if groups.count == 1 {
                        ForEach(group.sessions) { session in
                            sessionRow(session)
                        }
                    } else {
                        projectGroup(group)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.Colors.background)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(DS.Colors.borderSubtle.opacity(0.7))
                    .frame(height: 1)
            }
        }
    }

    @ViewBuilder
    private func projectGroup(_ group: (project: String, sessions: [VibeSession])) -> some View {
        let isExpanded = !collapsedProjects.contains(group.project)
        let activeCount = group.sessions.filter(\.isActive).count

        VStack(alignment: .leading, spacing: 4) {
            Button {
                if isExpanded {
                    collapsedProjects.insert(group.project)
                } else {
                    collapsedProjects.remove(group.project)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                    Text(group.project)
                        .font(.system(size: 11, weight: .semibold))
                    Text(activeCount > 0 ? "\(group.sessions.count) · \(activeCount) working" : "\(group.sessions.count)")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundColor(DS.Colors.textTertiary)
                    Spacer(minLength: 0)
                }
                .foregroundColor(DS.Colors.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(group.sessions) { session in
                    sessionRow(session)
                        .padding(.leading, 12)
                }
            }
        }
    }

    private func sessionRow(_ session: VibeSession) -> some View {
        HStack(spacing: 6) {
            Button {
                onSelect(session)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(session.isActive ? DS.Colors.success : DS.Colors.textTertiary)
                        .frame(width: 6, height: 6)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(session.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.Colors.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Text(detailLine(for: session))
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(DS.Colors.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.Colors.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open transcript")

            Button {
                openInTerminal(session.workingDirectory)
            } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.textTertiary)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open this project in Terminal")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Opens Terminal in the session's project directory — the "jump to
    /// where this agent works" affordance.
    private func openInTerminal(_ directory: String) {
        guard !directory.isEmpty else { return }
        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments = ["-a", "Terminal", directory]
        try? opener.run()
    }

    private func detailLine(for session: VibeSession) -> String {
        let cost = String(format: "$%.2f", session.costUsd)
        if session.isActive {
            return "\(session.projectName) · working… · \(cost)"
        }
        let ago = relativeAge(of: session.endedAt ?? session.startedAt)
        return "\(session.projectName) · done \(ago) · \(cost)"
    }

    private func relativeAge(of date: Date) -> String {
        let seconds = max(0, Date().timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        return "\(Int(seconds / 3600))h ago"
    }
}

#Preview("Sessions strip — two projects") {
    VibeSessionsStrip(sessions: [
        VibeSession(
            id: "a", title: "Fix the discount bug in pricing.py",
            workingDirectory: "/Users/demo/demo-repo", isActive: true,
            costUsd: 0.04, startedAt: Date().addingTimeInterval(-120), endedAt: nil
        ),
        VibeSession(
            id: "b", title: "Summarize the README",
            workingDirectory: "/Users/demo/demo-repo", isActive: false,
            costUsd: 0.02, startedAt: Date().addingTimeInterval(-900),
            endedAt: Date().addingTimeInterval(-600)
        ),
        VibeSession(
            id: "c", title: "Refactor the landing hero",
            workingDirectory: "/Users/demo/landing", isActive: false,
            costUsd: 0.11, startedAt: Date().addingTimeInterval(-1500),
            endedAt: Date().addingTimeInterval(-1400)
        ),
    ])
    .frame(width: 400)
    .background(DS.Colors.background)
}
