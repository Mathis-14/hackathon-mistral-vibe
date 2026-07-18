//
//  VibeBuddyChatController.swift
//  Vibe Buddy
//
//  Owns the chat transcript shown in VibeBuddyPanelView and drives the
//  worker round-trip: user text in → streamed assistant reply out (live
//  worker on 127.0.0.1:8787, or the built-in replay when the worker is
//  unreachable / "vibebuddy.chatMode" == "replay").
//

import Combine
import Foundation
import SwiftUI

@MainActor
final class VibeBuddyChatController: ObservableObject {
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var isStreaming = false
    /// True when the last reply came from the replay fixture — the UI can
    /// badge it so a rehearsal never gets mistaken for a live run.
    @Published private(set) var lastReplyWasReplayed = false

    func submit(_ text: String) {
        guard !isStreaming else { return }
        messages.append(ChatMessage(id: UUID(), role: .user, text: text))
        isStreaming = true

        let history = messages.map { message in
            (role: message.role == .user ? "user" : "assistant", content: message.text)
        }

        Task {
            var assistantMessageId: UUID?
            do {
                let result = try await WorkerChatReplay.streamReply(messages: history) { [weak self] delta in
                    guard let self else { return }
                    if let id = assistantMessageId,
                       let index = self.messages.firstIndex(where: { $0.id == id }) {
                        self.messages[index].text += delta
                    } else {
                        let message = ChatMessage(id: UUID(), role: .assistant, text: delta)
                        assistantMessageId = message.id
                        self.messages.append(message)
                    }
                }
                lastReplyWasReplayed = result.isReplayed
            } catch {
                let explanation = "I couldn't reach the worker (\(error.localizedDescription)). Check that wrangler dev is running on 127.0.0.1:8787, or set chat mode to replay."
                messages.append(ChatMessage(id: UUID(), role: .assistant, text: explanation))
            }
            isStreaming = false
        }
    }
}

/// Bridges the observable controller to the closure-driven panel view so
/// MenuBarPanelManager can host a plain NSHostingView.
struct VibeBuddyPanelContainer: View {
    @ObservedObject var controller: VibeBuddyChatController

    var body: some View {
        VibeBuddyPanelView(
            messages: controller.messages,
            isStreaming: controller.isStreaming,
            onSubmit: { [weak controller] text in controller?.submit(text) }
        )
    }
}
