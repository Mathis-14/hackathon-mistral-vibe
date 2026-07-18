//
//  VibeSessionsStrip.swift
//  Vibe Buddy
//
//  Compact panel section showing local Mistral Vibe Code CLI sessions
//  (read-only, fed by VibeSessionWatcher). Hidden entirely when there is
//  nothing recent — the panel stays clean for non-Vibe-Code users.
//

import SwiftUI

struct VibeSessionsStrip: View {
    let sessions: [VibeSession]
    /// Called when a session row is clicked — the container opens the
    /// transcript inspector. Defaulted so existing call sites compile.
    var onSelect: (VibeSession) -> Void = { _ in }

    var body: some View {
        if sessions.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("VIBE CODE SESSIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundColor(DS.Colors.textTertiary)

                ForEach(sessions) { session in
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(DS.Colors.surface1, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("Open transcript")
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

#Preview("Sessions strip") {
    VibeSessionsStrip(sessions: [
        VibeSession(
            id: "session_20260718_094422_7098a039",
            title: "Fix the discount bug in pricing.py",
            workingDirectory: "/Users/demo/demo-repo",
            isActive: true,
            costUsd: 0.0412,
            startedAt: Date().addingTimeInterval(-120),
            endedAt: nil
        ),
        VibeSession(
            id: "session_20260718_094599_11223344",
            title: "Summarize the README",
            workingDirectory: "/Users/demo/demo-repo",
            isActive: false,
            costUsd: 0.021,
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date().addingTimeInterval(-600)
        ),
    ])
    .frame(width: 400)
    .background(DS.Colors.background)
}
