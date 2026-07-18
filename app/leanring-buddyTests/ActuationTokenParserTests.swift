//
//  ActuationTokenParserTests.swift
//  Unit tests for the [OPEN_APP:] token parser, especially delta-boundary
//  behavior: tokens split across deltas must never leak into display text,
//  and bracket text that is NOT a token must never be swallowed.
//

import XCTest
@testable import VibeBuddy

final class ActuationTokenParserTests: XCTestCase {

    func testTokenSplitAcrossThreeDeltas() {
        var parser = ActuationTokenParser()

        let first = parser.feed(delta: "Sure — [OPE")
        XCTAssertEqual(first.displayText, "Sure — ", "Partial token prefix must be held back")
        XCTAssertEqual(first.appNames, [])

        let second = parser.feed(delta: "N_APP:Xco")
        XCTAssertEqual(second.displayText, "", "Still inside the token — nothing to display")
        XCTAssertEqual(second.appNames, [])

        let third = parser.feed(delta: "de] opening now")
        XCTAssertEqual(third.displayText, " opening now")
        XCTAssertEqual(third.appNames, ["Xcode"])
    }

    func testTokenMidSentence() {
        var parser = ActuationTokenParser()

        let result = parser.feed(delta: "Let me help — [OPEN_APP:Safari] is launching.")
        XCTAssertEqual(result.displayText, "Let me help —  is launching.")
        XCTAssertEqual(result.appNames, ["Safari"])
    }

    func testTwoTokensInOneDelta() {
        var parser = ActuationTokenParser()

        let result = parser.feed(delta: "[OPEN_APP:Xcode] and [OPEN_APP:Visual Studio Code] done")
        XCTAssertEqual(result.displayText, " and  done")
        XCTAssertEqual(result.appNames, ["Xcode", "Visual Studio Code"], "App names may contain spaces")
    }

    func testBracketButNotTokenStaysText() {
        var parser = ActuationTokenParser()

        let result = parser.feed(delta: "I like [OPEN_APPLE juice] a lot")
        XCTAssertEqual(result.displayText, "I like [OPEN_APPLE juice] a lot")
        XCTAssertEqual(result.appNames, [])
    }

    func testHeldPrefixResolvedAsTextAcrossDeltas() {
        var parser = ActuationTokenParser()

        let first = parser.feed(delta: "try [OPEN_A")
        XCTAssertEqual(first.displayText, "try ", "\"[OPEN_A\" could still become a token — held")
        XCTAssertEqual(first.appNames, [])

        let second = parser.feed(delta: "PPLE juice]!")
        XCTAssertEqual(second.displayText, "[OPEN_APPLE juice]!", "Once disproven, the held text is released verbatim")
        XCTAssertEqual(second.appNames, [])
    }

    func testFlushEmitsDanglingPrefix() {
        var parser = ActuationTokenParser()

        let result = parser.feed(delta: "done [OPEN_APP:Xc")
        XCTAssertEqual(result.displayText, "done ")
        XCTAssertEqual(result.appNames, [])

        XCTAssertEqual(parser.flush(), "[OPEN_APP:Xc", "End of stream releases the dangling partial as text")
        XCTAssertEqual(parser.flush(), "", "Flush must be idempotent")
    }

    func testTokenSplitCharacterByCharacter() {
        var parser = ActuationTokenParser()
        var display = ""
        var names: [String] = []

        for character in "Go [OPEN_APP:Music] now" {
            let result = parser.feed(delta: String(character))
            display += result.displayText
            names += result.appNames
        }
        display += parser.flush()

        XCTAssertEqual(display, "Go  now")
        XCTAssertEqual(names, ["Music"])
    }

    func testNewlineInsideCandidateIsNotAToken() {
        var parser = ActuationTokenParser()

        let first = parser.feed(delta: "[OPEN_APP:half")
        XCTAssertEqual(first.displayText, "")

        let second = parser.feed(delta: "\nnew line")
        XCTAssertEqual(second.displayText, "[OPEN_APP:half\nnew line", "A newline disproves the token — text is released")
        XCTAssertEqual(second.appNames, [])
    }
}
