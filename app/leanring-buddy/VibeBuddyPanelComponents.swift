//
//  VibeBuddyPanelComponents.swift
//  leanring-buddy
//
//  Building blocks for VibeBuddyPanelView: the pulsing status dot, the
//  role-styled chat bubbles (with streaming caret), the empty state, and
//  the rounded input bar. Kept separate so the panel view reads as layout
//  and these read as styling.
//

import SwiftUI

// MARK: - Status Dot

/// Small pulsing presence dot: green when idle ("ready"), Mistral orange
/// while a reply is streaming. A soft ring expands and fades on a loop.
struct VibeBuddyStatusDot: View {
    let isStreaming: Bool

    @State private var isPulsing = false

    private var dotColor: Color {
        isStreaming ? DS.Colors.accent : DS.Colors.success
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(dotColor.opacity(isPulsing ? 0 : 0.5), lineWidth: 1.5)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 2.4 : 1.0)

            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: dotColor.opacity(0.6), radius: 4)
        }
        .frame(width: 20, height: 20)
        .animation(.easeOut(duration: DS.Animation.normal), value: isStreaming)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Chat Bubble

/// One transcript bubble. User messages sit right-aligned in an
/// orange-tinted bubble; assistant messages sit left-aligned on a surface
/// bubble. When `showsCaret` is true (streaming), a blinking caret is
/// appended inline after the text.
struct VibeBuddyChatBubble: View {
    let message: ChatMessage
    var showsCaret: Bool = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(spacing: 0) {
            if isUser { Spacer(minLength: 48) }

            VStack(alignment: .trailing, spacing: 4) {
                bubbleContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(bubbleBackground)
                    .overlay(bubbleShape.stroke(
                        isUser ? DS.Colors.accent.opacity(0.42) : DS.Colors.borderSubtle,
                        lineWidth: 1
                    ))

                if isUser && message.hasScreenshot {
                    screenshotCaption
                }
            }

            if !isUser { Spacer(minLength: 48) }
        }
    }

    /// Tiny right-aligned caption under a user bubble noting that a
    /// screenshot of the screen was attached to the request.
    private var screenshotCaption: some View {
        HStack(spacing: 3) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 9, weight: .medium))
            Text("screen attached")
                .font(.system(size: 10))
        }
        .foregroundColor(DS.Colors.textTertiary)
    }

    /// User bubbles get a soft top-to-bottom orange gradient so they read
    /// as glowing Mistral orange instead of a flat muddy tint on the dark
    /// background; assistant bubbles stay on the flat elevated surface.
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

    @ViewBuilder
    private var bubbleContent: some View {
        if showsCaret {
            // TimelineView re-renders on a fixed cadence, giving the caret a
            // terminal-style blink without keeping any timer state around
            // once streaming ends.
            TimelineView(.periodic(from: .now, by: 0.45)) { context in
                let phase = Int(context.date.timeIntervalSinceReferenceDate / 0.45)
                styledText(caretOpacity: phase.isMultiple(of: 2) ? 1.0 : 0.15)
            }
        } else {
            styledText(caretOpacity: nil)
        }
    }

    /// Message content split into prose and fenced code segments so code
    /// renders as real code blocks (```lang fences, monospaced, boxed).
    /// Prose gets inline-markdown treatment (bold, `code`, links).
    private enum MessageSegment: Equatable {
        case prose(String)
        case code(String)
    }

    private static func segments(from text: String) -> [MessageSegment] {
        var segments: [MessageSegment] = []
        var prose: [String] = []
        var code: [String] = []
        var inCode = false
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if inCode {
                    segments.append(.code(code.joined(separator: "\n")))
                    code = []
                } else if !prose.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.prose(prose.joined(separator: "\n").trimmingCharacters(in: .newlines)))
                    prose = []
                } else {
                    prose = []
                }
                inCode.toggle()
                continue
            }
            if inCode {
                code.append(line)
            } else {
                prose.append(line)
            }
        }
        if inCode, !code.joined().isEmpty {
            segments.append(.code(code.joined(separator: "\n")))  // unclosed fence mid-stream
        } else if !prose.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(.prose(prose.joined(separator: "\n").trimmingCharacters(in: .newlines)))
        }
        return segments
    }

    private func inlineMarkdown(_ prose: String) -> AttributedString {
        (try? AttributedString(
            markdown: prose,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(prose)
    }

    private func styledText(caretOpacity: Double?) -> some View {
        let segments = Self.segments(from: message.text)
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                switch segment {
                case .prose(let prose):
                    proseText(prose, caretOpacity: index == segments.count - 1 ? caretOpacity : nil)
                case .code(let code):
                    Text(verbatim: code)
                        .font(.system(size: 11.5, design: .monospaced))
                        .lineSpacing(2)
                        .foregroundColor(DS.Colors.textPrimary)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(DS.Colors.borderSubtle, lineWidth: 1)
                        )
                }
            }
            if segments.isEmpty, let caretOpacity {
                proseText("", caretOpacity: caretOpacity)
            }
        }
        .multilineTextAlignment(.leading)
    }

    private func proseText(_ prose: String, caretOpacity: Double?) -> some View {
        var text = Text(inlineMarkdown(prose))
        if let caretOpacity {
            text = text + Text(verbatim: prose.isEmpty ? "▍" : " ▍")
                .foregroundColor(DS.Colors.accentText.opacity(caretOpacity))
        }
        return text
            .font(.system(size: 13))
            .lineSpacing(3)
            .foregroundColor(DS.Colors.textPrimary)
            .textSelection(.enabled)
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

// MARK: - Thinking Bubble

/// Shown while streaming before any assistant text has arrived: an
/// assistant-shaped bubble holding just the blinking caret.
struct VibeBuddyThinkingBubble: View {
    var body: some View {
        VibeBuddyChatBubble(
            message: ChatMessage(id: UUID(), role: .assistant, text: ""),
            showsCaret: true
        )
    }
}

// MARK: - Empty State

/// Friendly first-run hint shown when the transcript is empty.
struct VibeBuddyEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(DS.Colors.accentSubtle)
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(DS.Colors.accent.opacity(0.25), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(DS.Colors.accentText)
            }

            VStack(spacing: 6) {
                Text("Ask me anything")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.Colors.textPrimary)

                Text("Vibe Buddy answers right here, over whatever\nyou're working on — summon it from anywhere.")
                    .font(.system(size: 12))
                    .foregroundColor(DS.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
            }
        }
        // Slight upward optical shift — dead-center reads as "sunk" under
        // the heavier footer.
        .offset(y: -10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Input Bar

/// The rounded composer at the bottom of the panel: decorative mic glyph
/// (voice lands in v1), plain text field, and a circular send button.
/// Return submits; the field clears itself after submitting.
struct VibeBuddyInputBar: View {
    let onSubmit: (String) -> Void

    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSend: Bool { !trimmedDraft.isEmpty }

    var body: some View {
        HStack(spacing: 8) {
            // Decorative in v0 — push-to-talk voice arrives with Voxtral in v1.
            Image(systemName: "mic.fill")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.Colors.textTertiary)
                .frame(width: 24, height: 24)

            TextField(
                "",
                text: $draft,
                prompt: Text("Type / for quick access")
                    .foregroundColor(DS.Colors.textTertiary)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .foregroundColor(DS.Colors.textPrimary)
            .tint(DS.Colors.accent)
            .focused($isFocused)
            .onSubmit(submit)
            .overlay(IBeamCursorView())

            Button(action: submit) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(canSend ? DS.Colors.textOnAccent : DS.Colors.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(canSend ? DS.Colors.accent : DS.Colors.surface3)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .pointerCursor(isEnabled: canSend)
            .animation(.easeOut(duration: DS.Animation.fast), value: canSend)
        }
        .padding(.leading, 12)
        .padding(.trailing, 5)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DS.Colors.surface2))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(
                isFocused ? DS.Colors.accent.opacity(0.45) : DS.Colors.borderSubtle,
                lineWidth: 1
            )
        )
        .animation(.easeOut(duration: DS.Animation.fast), value: isFocused)
        .onAppear {
            // Focus the field as soon as the panel appears so the user can
            // type immediately after summoning.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
        }
    }

    private func submit() {
        let text = trimmedDraft
        guard !text.isEmpty else { return }
        onSubmit(text)
        draft = ""
    }
}
