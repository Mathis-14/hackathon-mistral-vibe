//
//  SSEEventParserTests.swift
//  Unit tests for the worker /chat SSE parser, especially chunk-boundary behavior.
//

import XCTest
@testable import VibeBuddy

final class SSEEventParserTests: XCTestCase {

    func testEventSplitAcrossTwoChunks() {
        var parser = SSEEventParser()

        let firstChunkEvents = parser.feed(chunk: "data: {\"type\":\"delta\",\"te")
        XCTAssertEqual(firstChunkEvents, [], "No event may be emitted before its newline arrives")

        let secondChunkEvents = parser.feed(chunk: "xt\":\"Hello\"}\n\n")
        XCTAssertEqual(secondChunkEvents, [.delta("Hello")])
    }

    func testTwoEventsInOneChunk() {
        var parser = SSEEventParser()

        let events = parser.feed(
            chunk: "data: {\"type\":\"delta\",\"text\":\"Hel\"}\n\ndata: {\"type\":\"delta\",\"text\":\"lo\"}\n\n"
        )
        XCTAssertEqual(events, [.delta("Hel"), .delta("lo")])
    }

    func testDoneEvent() {
        var parser = SSEEventParser()

        let events = parser.feed(chunk: "data: {\"type\":\"delta\",\"text\":\"Hi\"}\n\ndata: {\"type\":\"done\"}\n\n")
        XCTAssertEqual(events, [.delta("Hi"), .done])
    }

    func testBareDoneSentinelTolerated() {
        var parser = SSEEventParser()

        let events = parser.feed(chunk: "data: [DONE]\n")
        XCTAssertEqual(events, [.done])
    }

    func testGarbageCommentAndBlankLinesIgnored() {
        var parser = SSEEventParser()

        let events = parser.feed(
            chunk: ": keep-alive\n\nnot-an-sse-line\ndata: {broken json!!\ndata: {\"type\":\"delta\",\"text\":\"ok\"}\n"
        )
        XCTAssertEqual(events, [.delta("ok")], "Comments, blanks, and garbage must never abort the stream")
    }

    func testCRLFLineEndings() {
        var parser = SSEEventParser()

        let events = parser.feed(chunk: "data: {\"type\":\"delta\",\"text\":\"x\"}\r\n\r\n")
        XCTAssertEqual(events, [.delta("x")])
    }

    func testDeltaSplitAcrossManyTinyChunks() {
        var parser = SSEEventParser()
        var collected: [SSEEventParser.ParsedEvent] = []

        for character in "data: {\"type\":\"delta\",\"text\":\"abc\"}\ndata: [DONE]\n" {
            collected.append(contentsOf: parser.feed(chunk: String(character)))
        }
        XCTAssertEqual(collected, [.delta("abc"), .done])
    }
    func testCanonicalWorkerShapeContentBlockDelta() {
        var parser = SSEEventParser()
        let events = parser.feed(chunk: """
        event: message_start
        data: {"type":"message_start","message":{"id":"msg_1","role":"assistant"}}

        event: content_block_delta
        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello "}}

        data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"world"}}

        event: message_stop
        data: {"type":"message_stop"}

        """)
        XCTAssertEqual(events, [.delta("Hello "), .delta("world"), .done])
    }

}
