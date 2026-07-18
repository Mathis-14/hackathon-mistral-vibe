//
//  VibeSessionTranscriptView.swift
//  Vibe Buddy
//
//  Read-only transcript of a local Vibe Code CLI session
//  (~/.vibe/logs/session/<dir>/messages.jsonl) plus a one-line steering
//  composer: "Steer this agent…" resumes the session via
//  `vibe --resume <session_id> -p <task>` (VibeAgentLauncher.resume).
//
//  A resume writes a NEW session directory carrying the full history
//  (verified live on vibe 2.21.0), so after steering the view retargets to
//  that directory and keeps polling every 2s — the transcript grows live
//  while the steered agent works, and the sessions strip shows it active.
//

import Combine
import SwiftUI

// MARK: - Transcript model

struct VibeTranscriptEntry: Identifiable, Equatable {
    enum Kind: Equatable {
        case user(String)
        case assistant(String)
        /// Tool activity, rendered as a small chip with the tool name.
        case tool(String)
    }

    /// Stable across re-parses: derived from the jsonl line index.
    let id: Int
    let kind: Kind
}

// MARK: - Loader (pure reads over ~/.vibe/logs/session)

enum VibeSessionTranscriptLoader {
    static let sessionsDirectory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".vibe/logs/session", isDirectory: true)

    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Parses messages.jsonl into renderable entries, oldest first.
    /// Message shape (verified live on vibe 2.21.0): one JSON object per
    /// line — {role: system|user|assistant|tool, content: String?,
    /// tool_calls: [{id, function: {name}}]?, name: String?, tool_call_id?}.
    /// System messages and empty contents are skipped; assistant tool_calls
    /// and tool-role results both map to chips, deduped by tool_call_id so
    /// one call renders one chip.
    static func entries(forSessionDirectory directoryId: String) -> [VibeTranscriptEntry] {
        let url = sessionsDirectory
            .appendingPathComponent(directoryId, isDirectory: true)
            .appendingPathComponent("messages.jsonl")
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return [] }

        var entries: [VibeTranscriptEntry] = []
        var chippedToolCallIds: Set<String> = []
        var lineIndex = 0

        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            defer { lineIndex += 1 }
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let role = json["role"] as? String else { continue }

            let content = (json["content"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            switch role {
            case "user":
                guard !content.isEmpty else { continue }
                entries.append(VibeTranscriptEntry(id: lineIndex * 8, kind: .user(content)))

            case "assistant":
                if !content.isEmpty {
                    entries.append(VibeTranscriptEntry(id: lineIndex * 8, kind: .assistant(content)))
                }
                for (offset, call) in ((json["tool_calls"] as? [[String: Any]]) ?? []).enumerated() {
                    if let callId = call["id"] as? String {
                        chippedToolCallIds.insert(callId)
                    }
                    if let function = call["function"] as? [String: Any],
                       let name = function["name"] as? String {
                        entries.append(VibeTranscriptEntry(id: lineIndex * 8 + 1 + offset, kind: .tool(name)))
                    }
                }

            case "tool":
                // Chip only when the assistant side of the call was not
                // already rendered as one.
                let callId = json["tool_call_id"] as? String
                if let name = json["name"] as? String,
                   callId.map({ !chippedToolCallIds.contains($0) }) ?? true {
                    entries.append(VibeTranscriptEntry(id: lineIndex * 8, kind: .tool(name)))
                }

            default:
                continue // system
            }
        }
        return entries
    }

    struct Meta: Equatable {
        var title: String = ""
        var isActive: Bool = false
        var costUsd: Double = 0
    }

    /// Live status + cost straight from the session's meta.json — polled so
    /// a steered session flips to "working…" in the header within 2s.
    static func meta(forSessionDirectory directoryId: String) -> Meta? {
        let url = sessionsDirectory
            .appendingPathComponent(directoryId, isDirectory: true)
            .appendingPathComponent("meta.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let stats = json["stats"] as? [String: Any] ?? [:]
        let promptTokens = (stats["session_prompt_tokens"] as? Double) ?? 0
        let completionTokens = (stats["session_completion_tokens"] as? Double) ?? 0
        let inputPrice = (stats["input_price_per_million"] as? Double) ?? 0
        let outputPrice = (stats["output_price_per_million"] as? Double) ?? 0
        return Meta(
            title: (json["title"] as? String) ?? "",
            isActive: (json["end_time"] as? String) == nil,
            costUsd: (promptTokens * inputPrice + completionTokens * outputPrice) / 1_000_000
        )
    }

    /// Finds the session directory a `vibe --resume` created after a steer:
    /// the newest directory (excluding the one on screen) started at or
    /// after the steer time, in the same working directory.
    static func resumedSessionDirectory(
        after steerDate: Date,
        workingDirectory: String,
        excluding excludedId: String
    ) -> String? {
        let fileManager = FileManager.default
        guard let directories = try? fileManager.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else { return nil }

        let newestFirst = directories.sorted { lhs, rhs in
            modificationDate(of: lhs) > modificationDate(of: rhs)
        }.prefix(10)

        for directory in newestFirst {
            let directoryId = directory.lastPathComponent
            guard directoryId != excludedId,
                  let data = try? Data(contentsOf: directory.appendingPathComponent("meta.json")),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let startString = json["start_time"] as? String,
                  let start = parseDate(startString),
                  start >= steerDate.addingTimeInterval(-3) else { continue }
            let environment = json["environment"] as? [String: Any] ?? [:]
            let directoryPath = (environment["working_directory"] as? String) ?? ""
            if directoryPath == workingDirectory {
                return directoryId
            }
        }
        return nil
    }

    private static func parseDate(_ string: String) -> Date? {
        isoParser.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
    }
}

// MARK: - Transcript View

struct VibeSessionTranscriptView: View {
    let session: VibeSession
    /// Clears the selection in the panel container (back chevron).
    let onBack: () -> Void

    /// Directory currently rendered — retargets to the resume-created
    /// directory after a steer.
    @State private var activeDirectoryId: String
    @State private var entries: [VibeTranscriptEntry] = []
    @State private var meta: VibeSessionTranscriptLoader.Meta?

    /// Steer text shown as an optimistic user bubble until the resumed
    /// session's own jsonl takes over.
    @State private var pendingSteer: String?
    @State private var steeredAt: Date?
    @State private var steerFailed = false
    @State private var steerDraft = ""
    @FocusState private var isSteerFocused: Bool

    private let pollTimer = Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()
    private let bottomAnchorID = "vibebuddy.sessiontranscript.bottom"

    init(session: VibeSession, onBack: @escaping () -> Void) {
        self.session = session
        self.onBack = onBack
        _activeDirectoryId = State(initialValue: session.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(DS.Colors.borderSubtle.opacity(0.7))
                .frame(height: 1)

            transcript

            steerFooter
        }
        .background(DS.Colors.background)
        .onAppear(perform: refresh)
        .onReceive(pollTimer) { _ in refresh() }
    }

    // MARK: Header

    private var isWorking: Bool {
        (meta?.isActive ?? session.isActive) || steeredAt != nil
    }

    private var statusLine: String {
        let cost = String(format: "$%.2f", meta?.costUsd ?? session.costUsd)
        if steeredAt != nil && !(meta?.isActive ?? false) {
            return "\(session.projectName) · resuming… · \(cost)"
        }
        if isWorking {
            return "\(session.projectName) · working… · \(cost)"
        }
        return "\(session.projectName) · done · \(cost)"
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textSecondary)
                    .frame(width: 24, height: 24)
                    .background(DS.Colors.surface2, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Back to sessions")

            Circle()
                .fill(isWorking ? DS.Colors.success : DS.Colors.textTertiary)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(session.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(statusLine)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(DS.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Image(systemName: "terminal")
                .font(.system(size: 11))
                .foregroundColor(DS.Colors.textTertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    // MARK: Transcript

    @ViewBuilder
    private var transcript: some View {
        if entries.isEmpty && pendingSteer == nil {
            VStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 20))
                    .foregroundColor(DS.Colors.textTertiary)
                Text("No transcript yet")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(entries) { entry in
                            entryView(entry)
                        }

                        if let pendingSteer {
                            TranscriptBubble(text: pendingSteer, isUser: true)
                            Text("resuming agent…")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(DS.Colors.textTertiary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .onChange(of: entries) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                    }
                }
                .onChange(of: pendingSteer) {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
                .onAppear {
                    proxy.scrollTo(bottomAnchorID, anchor: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func entryView(_ entry: VibeTranscriptEntry) -> some View {
        switch entry.kind {
        case .user(let text):
            TranscriptBubble(text: text, isUser: true)
        case .assistant(let text):
            TranscriptBubble(text: text, isUser: false)
        case .tool(let name):
            HStack(spacing: 4) {
                Text("🔧")
                    .font(.system(size: 9))
                Text(name)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(DS.Colors.textSecondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(DS.Colors.surface1, in: Capsule())
            .overlay(Capsule().stroke(DS.Colors.borderSubtle, lineWidth: 1))
        }
    }

    // MARK: Steer footer

    private var trimmedSteerDraft: String {
        steerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var steerFooter: some View {
        VStack(spacing: 4) {
            Rectangle()
                .fill(DS.Colors.borderSubtle.opacity(0.7))
                .frame(height: 1)

            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $steerDraft,
                    prompt: Text("Steer this agent…")
                        .foregroundColor(DS.Colors.textTertiary)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(DS.Colors.textPrimary)
                .tint(DS.Colors.accent)
                .focused($isSteerFocused)
                .onSubmit(steer)

                Button(action: steer) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(trimmedSteerDraft.isEmpty ? DS.Colors.textTertiary : DS.Colors.textOnAccent)
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(trimmedSteerDraft.isEmpty ? DS.Colors.surface3 : DS.Colors.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(trimmedSteerDraft.isEmpty)
            }
            .padding(.leading, 10)
            .padding(.trailing, 4)
            .padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.Colors.surface2))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(
                    isSteerFocused ? DS.Colors.accent.opacity(0.45) : DS.Colors.borderSubtle,
                    lineWidth: 1
                )
            )
            .padding(.horizontal, 10)
            .padding(.top, 6)

            if steerFailed {
                Text("Couldn't resume — is the Vibe Code CLI installed?")
                    .font(.system(size: 10))
                    .foregroundColor(DS.Colors.destructiveText)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: Actions

    private func steer() {
        let task = trimmedSteerDraft
        guard !task.isEmpty else { return }
        guard !session.resumeId.isEmpty else {
            steerFailed = true
            return
        }

        let started = VibeAgentLauncher.resume(
            sessionId: session.resumeId,
            task: task,
            workingDirectory: session.workingDirectory
        )
        if started {
            steerFailed = false
            pendingSteer = task
            steeredAt = Date()
            steerDraft = ""
        } else {
            steerFailed = true
        }
    }

    private func refresh() {
        // After a steer, `vibe --resume` starts a NEW session directory that
        // carries the whole history — retarget the view to it once it lands.
        if let steeredAt,
           let resumedId = VibeSessionTranscriptLoader.resumedSessionDirectory(
               after: steeredAt,
               workingDirectory: session.workingDirectory,
               excluding: activeDirectoryId
           ) {
            activeDirectoryId = resumedId
            self.steeredAt = nil
            pendingSteer = nil
        }

        let parsed = VibeSessionTranscriptLoader.entries(forSessionDirectory: activeDirectoryId)
        if parsed != entries { entries = parsed }
        meta = VibeSessionTranscriptLoader.meta(forSessionDirectory: activeDirectoryId)
    }
}

// MARK: - Local bubble

/// Lightweight transcript bubble — same visual language as
/// VibeBuddyChatBubble (orange-tinted user right, surface assistant left)
/// but deliberately local: plain inline markdown, no caret/screenshot
/// machinery, so the shared chat bubble stays untouched.
private struct TranscriptBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 40) }

            Text(inlineMarkdown(text))
                .font(.system(size: 12))
                .lineSpacing(2.5)
                .foregroundColor(DS.Colors.textPrimary)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(bubbleBackground)
                .overlay(bubbleShape.stroke(
                    isUser ? DS.Colors.accent.opacity(0.42) : DS.Colors.borderSubtle,
                    lineWidth: 1
                ))

            if !isUser { Spacer(minLength: 40) }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private func inlineMarkdown(_ prose: String) -> AttributedString {
        (try? AttributedString(
            markdown: prose,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(prose)
    }

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            bubbleShape.fill(
                LinearGradient(
                    colors: [
                        DS.Colors.accent.opacity(0.26),
                        DS.Colors.accent.opacity(0.13),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        } else {
            bubbleShape.fill(DS.Colors.surface2)
        }
    }

    private var bubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 8,
            bottomLeadingRadius: isUser ? 8 : 3,
            bottomTrailingRadius: isUser ? 3 : 8,
            topTrailingRadius: 8,
            style: .continuous
        )
    }
}

// MARK: - Preview

#Preview("Session transcript") {
    VibeSessionTranscriptView(
        session: VibeSession(
            id: "session_20260718_094422_7098a039",
            title: "Fix the discount bug in pricing.py",
            workingDirectory: "/Users/demo/demo-repo",
            isActive: false,
            costUsd: 0.0412,
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date().addingTimeInterval(-60),
            resumeId: "7098a039-0000-0000-0000-000000000000"
        ),
        onBack: { print("back") }
    )
    .frame(width: 400, height: 560)
    .background(DS.Colors.background)
}
