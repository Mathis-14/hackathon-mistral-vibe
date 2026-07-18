//
//  ActuationTokenParser.swift
//  Vibe Buddy
//
//  Incremental scanner for [OPEN_APP:AppName] actuation tokens inside a
//  streamed token flow. A token may be split across any number of deltas,
//  so the parser holds back any trailing text that could still become a
//  token (e.g. "[OPEN_A") and only releases it as display text once it is
//  proven NOT to be a token. App names may contain spaces.
//
//  This is the single boundary where actuation tokens are parsed
//  (AGENTS.md: "parse at the boundary") — nothing else in the app should
//  ever string-match "[OPEN_APP:".
//

import Foundation

struct ActuationTokenParser {

    /// The literal opening of an actuation token, up to and including the colon.
    private static let tokenPrefix: [Character] = Array("[OPEN_APP:")

    /// Safety cap on the app-name portion: if no closing "]" shows up within
    /// this many characters, the candidate is declared not-a-token so a
    /// malformed stream can never swallow the rest of the reply.
    private static let maxAppNameLength = 128

    /// Trailing text from previous deltas that could still turn into a token.
    /// Always either empty or starting with "[".
    private var heldBuffer: [Character] = []

    /// Feeds one streamed delta.
    ///
    /// - Returns: `displayText` — the text to append to the visible transcript
    ///   (complete tokens stripped, an unresolved partial token held back), and
    ///   `appNames` — the names from every token completed by this delta, in order.
    mutating func feed(delta: String) -> (displayText: String, appNames: [String]) {
        let characters = heldBuffer + Array(delta)
        heldBuffer = []

        var displayText = ""
        var appNames: [String] = []
        var index = 0

        while index < characters.count {
            // Everything before the next "[" is plain text.
            guard let bracketIndex = characters[index...].firstIndex(of: "[") else {
                displayText.append(contentsOf: characters[index...])
                break
            }
            displayText.append(contentsOf: characters[index..<bracketIndex])

            switch Self.matchToken(in: characters, from: bracketIndex) {
            case .complete(let appName, let continueFrom):
                appNames.append(appName)
                index = continueFrom
            case .partial:
                // Could still become a token — hold it back until resolved.
                heldBuffer = Array(characters[bracketIndex...])
                index = characters.count
            case .notAToken:
                // The "[" was ordinary text; emit it and rescan what follows
                // (it may itself contain a real token, e.g. "[[OPEN_APP:X]").
                displayText.append("[")
                index = bracketIndex + 1
            }
        }

        return (displayText, appNames)
    }

    /// End of stream: whatever is still held back can no longer become a
    /// token, so it is released as plain display text.
    mutating func flush() -> String {
        let remainder = String(heldBuffer)
        heldBuffer = []
        return remainder
    }

    // MARK: - Matching

    private enum TokenMatch {
        /// A full "[OPEN_APP:Name]" token; `continueFrom` is the index just past "]".
        case complete(appName: String, continueFrom: Int)
        /// The characters so far are a strict prefix of a possible token.
        case partial
        /// Proven not to be a token — treat the "[" as ordinary text.
        case notAToken
    }

    private static func matchToken(in characters: [Character], from start: Int) -> TokenMatch {
        // 1. Match the literal "[OPEN_APP:" prefix.
        var index = start
        for expected in tokenPrefix {
            guard index < characters.count else { return .partial }
            guard characters[index] == expected else { return .notAToken }
            index += 1
        }

        // 2. Scan the app name up to the closing "]".
        var appName = ""
        while index < characters.count {
            let character = characters[index]
            if character == "]" {
                let trimmed = appName.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return .notAToken }
                return .complete(appName: trimmed, continueFrom: index + 1)
            }
            // A newline inside a token is never valid — bail out as text.
            if character == "\n" || character == "\r" { return .notAToken }
            appName.append(character)
            if appName.count > maxAppNameLength { return .notAToken }
            index += 1
        }
        return .partial
    }
}
