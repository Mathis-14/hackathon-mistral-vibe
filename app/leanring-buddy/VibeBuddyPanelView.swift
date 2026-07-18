//
//  VibeBuddyPanelView.swift
//  leanring-buddy
//
//  The Vibe Buddy chat panel — the SwiftUI content hosted inside the menu
//  bar panel. A ~400x560 dark, rounded chat surface: pulsing status header,
//  scrollable transcript with role-styled bubbles and a streaming caret,
//  and a rounded composer with mic placeholder + send.
//
//  The view is intentionally dumb: it takes plain data + closures only
//  (messages, isStreaming, onSubmit) so CompanionManager can drive it
//  without the view knowing anything about networking or state machines.
//

import SwiftUI

// MARK: - Chat Model

/// The role of a chat transcript entry.
enum ChatRole {
    case user
    case assistant
}

/// A single chat transcript entry rendered as one bubble.
struct ChatMessage: Identifiable, Equatable {
    let id: UUID
    var role: ChatRole
    var text: String
    /// True when a screenshot of the user's screen was attached to this
    /// (user) message. Defaulted so all existing call sites keep compiling.
    var hasScreenshot: Bool = false
}

// MARK: - Vibe Buddy Panel

struct VibeBuddyPanelView: View {
    /// The full transcript, oldest first.
    let messages: [ChatMessage]
    /// True while the assistant reply is streaming in. The last assistant
    /// bubble shows an animated caret; if no assistant bubble exists yet,
    /// a "thinking" bubble with the caret is shown instead.
    let isStreaming: Bool
    /// Called with the trimmed input text when the user presses Return
    /// or clicks send. The view clears its own input field.
    let onSubmit: (String) -> Void
    /// Optional compact view rendered top-right in the header (e.g. the
    /// RoutinesBadge / a tab toggle). Defaulted so all existing call sites
    /// keep compiling unchanged.
    var headerAccessory: AnyView? = nil
    /// When non-nil, replaces the transcript area (header and composer stay)
    /// — the integrator passes RoutinesView here while the routines tab is
    /// active. Defaulted so all existing call sites keep compiling unchanged.
    var overrideContent: AnyView? = nil

    /// Optional strip pinned between the transcript and the composer —
    /// used for the live Vibe Code sessions section (D012). Hidden when nil.
    var belowTranscript: AnyView? = nil

    /// Optional banner pinned right under the header — used for the
    /// missing-permissions setup flow. Hidden when nil.
    var banner: AnyView? = nil

    /// The panel's natural size — the hosting NSPanel should match this.
    static let preferredSize = CGSize(width: 400, height: 560)

    private let bottomAnchorID = "vibebuddy.transcript.bottom"

    var body: some View {
        VStack(spacing: 0) {
            header

            Rectangle()
                .fill(DS.Colors.borderSubtle.opacity(0.7))
                .frame(height: 1)

            if let banner {
                banner
            }

            Group {
                if let overrideContent {
                    overrideContent
                } else {
                    transcript
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let belowTranscript {
                belowTranscript
            }

            footer
        }
        .frame(width: Self.preferredSize.width, height: Self.preferredSize.height)
        .background(DS.Colors.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Colors.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            VibeBuddyStatusDot(isStreaming: isStreaming)

            VStack(alignment: .leading, spacing: 1) {
                Text("Vibe Buddy")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Text("Mistral, one keystroke away")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Colors.textTertiary)
            }

            Spacer()

            if let headerAccessory {
                headerAccessory
            }

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 18, height: 18)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    // MARK: Transcript

    @ViewBuilder
    private var transcript: some View {
        if messages.isEmpty && !isStreaming {
            VibeBuddyEmptyState()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages) { message in
                            VibeBuddyChatBubble(
                                message: message,
                                showsCaret: isStreaming
                                    && message.role == .assistant
                                    && message.id == messages.last?.id
                            )
                        }

                        // The reply is on its way but no assistant text has
                        // arrived yet — show a lone thinking caret bubble.
                        if isStreaming && messages.last?.role != .assistant {
                            VibeBuddyThinkingBubble()
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorID)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .onChange(of: messages) {
                    scrollToBottom(proxy, animated: true)
                }
                .onChange(of: isStreaming) {
                    scrollToBottom(proxy, animated: true)
                }
                .onAppear {
                    scrollToBottom(proxy, animated: false)
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(bottomAnchorID, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorID, anchor: .bottom)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DS.Colors.borderSubtle.opacity(0.7))
                .frame(height: 1)

            VibeBuddyInputBar(onSubmit: onSubmit)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - Previews

#Preview("Empty state") {
    VibeBuddyPanelView(
        messages: [],
        isStreaming: false,
        onSubmit: { print("submit: \($0)") }
    )
    .padding(40)
    .background(Color(hex: "#D8D4CD"))
}

#Preview("Mid-stream") {
    VibeBuddyPanelView(
        messages: [
            ChatMessage(
                id: UUID(),
                role: .user,
                text: "What does this stack trace in my terminal mean?",
                hasScreenshot: true
            ),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                text: "It's a nil force-unwrap in your `parseChunk` function — the SSE frame arrived without a `data:` prefix, so the split returns"
            ),
        ],
        isStreaming: true,
        onSubmit: { print("submit: \($0)") }
    )
    .padding(40)
    .background(Color(hex: "#D8D4CD"))
}

#Preview("Override content (routines tab)") {
    let store = RoutineStore.previewStore(routines: [
        Routine(
            name: "Morning brief",
            prompt: "Short brief of the day: calendar, weather, headlines.",
            intervalMinutes: 60,
            isEnabled: true,
            lastRunAt: Date().addingTimeInterval(-300),
            lastArtifact: "Demo rehearsal at 18:30, judging at 21:00. Paris 24°C and clear."
        ),
    ])
    return VibeBuddyPanelView(
        messages: [],
        isStreaming: false,
        onSubmit: { print("submit: \($0)") },
        headerAccessory: AnyView(RoutinesBadge(store: store)),
        overrideContent: AnyView(
            RoutinesView(
                store: store,
                scheduler: RoutineScheduler(store: store, startsAutomatically: false)
            )
        )
    )
    .padding(40)
    .background(Color(hex: "#D8D4CD"))
}

#Preview("Long conversation") {
    VibeBuddyPanelView(
        messages: [
            ChatMessage(id: UUID(), role: .user, text: "Summarize the pull request I have open."),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                text: "PR #42 swaps the streaming backend to the new worker proxy: 3 files changed, the SSE parser moves into CompanionManager, and the retry logic now falls back to fixtures after 60s."
            ),
            ChatMessage(id: UUID(), role: .user, text: "Anything risky in there?"),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                text: "Two things to watch:\n1. The parser assumes every event ends with a blank line — a partial flush could stall the stream.\n2. The retry path isn't covered by the smoke script yet."
            ),
            ChatMessage(id: UUID(), role: .user, text: "Add a smoke check for the retry path then."),
            ChatMessage(
                id: UUID(),
                role: .assistant,
                text: "Done — I appended a step to scripts/smoke.sh that kills the worker mid-stream and asserts the client falls back to the fixture reply within 60 seconds."
            ),
        ],
        isStreaming: false,
        onSubmit: { print("submit: \($0)") }
    )
    .padding(40)
    .background(Color(hex: "#D8D4CD"))
}
