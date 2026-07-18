//
//  WorkerChatReplay.swift
//  Built-in replay fallback so the chat path works TODAY without the worker.
//
//  Mocks-first rule (AGENTS.md): the demo can never die on venue wifi or a
//  missing wrangler dev. Replay streams a realistic fixture through the exact
//  same onDelta path as the live client, at a realistic pace.
//

import Foundation

/// A finished chat reply, tagged with its origin so the UI can badge
/// replayed answers later.
struct ChatReplyResult: Equatable {
    /// The full reply text.
    let text: String
    /// True when the reply came from the built-in fixture, not the live worker.
    let isReplayed: Bool
}

/// Replay mode for the worker chat path.
///
/// The fixture streams whenever:
///  - UserDefaults "vibebuddy.chatMode" == "replay" (forced, e.g. for the stage), or
///  - the live worker connection is refused (wrangler dev not running).
enum WorkerChatReplay {

    /// UserDefaults key. Force replay from a terminal with:
    /// `defaults write com.vibebuddy.app vibebuddy.chatMode replay`
    static let chatModeDefaultsKey = "vibebuddy.chatMode"

    /// True when the user forced replay mode via UserDefaults.
    static var isReplayForced: Bool {
        UserDefaults.standard.string(forKey: chatModeDefaultsKey) == "replay"
    }

    /// Integrator entry point: streams from the live worker when it is
    /// reachable, otherwise falls back to the built-in fixture. `onDelta`
    /// receives each new text fragment on the main actor either way.
    /// `screenshotBase64` (raw base64 JPEG, no data-URI prefix) is forwarded
    /// to the live worker; replay ignores it.
    static func streamReply(
        messages: [(role: String, content: String)],
        screenshotBase64: String? = nil,
        client: WorkerChatClient = WorkerChatClient(),
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> ChatReplyResult {
        if isReplayForced {
            let text = try await streamFixtureReply(onDelta: onDelta)
            return ChatReplyResult(text: text, isReplayed: true)
        }

        do {
            let text = try await client.streamReply(
                messages: messages,
                screenshotBase64: screenshotBase64,
                onDelta: onDelta
            )
            return ChatReplyResult(text: text, isReplayed: false)
        } catch let error as WorkerChatError {
            guard case .connectionFailed = error else { throw error }
            // Worker unreachable — a hung call must not hang the demo:
            // fall through to the fixture (AGENTS.md time-box rule).
            let text = try await streamFixtureReply(onDelta: onDelta)
            return ChatReplyResult(text: text, isReplayed: true)
        }
    }

    /// Streams the built-in fixture word-by-word at ~20 chunks/second through
    /// the same onDelta path as the live client. Returns the full text.
    static func streamFixtureReply(
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        var accumulatedText = ""
        let words = fixtureReply.split(separator: " ", omittingEmptySubsequences: false)

        for (index, word) in words.enumerated() {
            let chunk = index == words.count - 1 ? String(word) : String(word) + " "
            accumulatedText += chunk
            await onDelta(chunk)
            try await Task.sleep(nanoseconds: 50_000_000) // ~20 chunks/second
        }
        return accumulatedText
    }

    /// Realistic fixture: a helpful Mistral answer about Swift code on screen.
    /// Mock data must look REAL on screen (AGENTS.md) — no lorem ipsum.
    ///
    /// The reply embeds exactly ONE `[OPEN_APP:Notes]` token mid-text so an
    /// offline rehearsal exercises the full hero moment: the token streams
    /// through the same word-chunk deltas as live replies, which drives
    /// ActuationTokenParser's incremental path end-to-end without a worker.
    private static let fixtureReply = """
        Looking at the `CompanionManager` on your screen, the streaming handler is \
        mostly right, but there is one real bug: you append each incoming chunk to \
        `accumulatedText` from the URLSession task, then SwiftUI reads it without \
        hopping to the main actor, so the panel can redraw mid-mutation — that is \
        the flicker you are seeing. Mark the append `@MainActor` (or wrap it in \
        `await MainActor.run { ... }`) and it goes away.

        I'll open Notes so you can keep these steps handy while you refactor. \
        [OPEN_APP:Notes] Now, about the retry logic — two smaller things worth \
        fixing while you are in there:

        1. The request timeout is 120 seconds — for an interactive panel, 60 seconds \
        with a single retry keeps a hung call from freezing the UI.
        2. `guard line.hasPrefix("data: ")` silently drops `data:` lines that arrive \
        without the space; matching on `data:` and trimming the payload is safer \
        across proxies.

        Want me to sketch the `@MainActor` refactor for you?
        """
}
