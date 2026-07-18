//
//  WorkerChatClient.swift
//  Streaming chat client for the Vibe Buddy Cloudflare Worker proxy.
//
//  Contract: see app/CHAT_CONTRACT.md (draft — canonical version lives in
//  worker/src/index.ts). If the contract changes, change SSEEventParser and
//  the worker in the same commit (AGENTS.md rule).
//

import Foundation

// MARK: - SSE parsing

/// Incremental Server-Sent-Events parser for the worker's /chat stream.
///
/// Feed it raw chunks exactly as they arrive off the wire — a chunk may split
/// an event anywhere, including mid-line — and it returns the events each
/// chunk completes. Partial trailing lines stay buffered until their newline
/// arrives. Standalone and init-less so it is unit-testable across chunk
/// boundaries without any networking.
struct SSEEventParser {

    /// One parsed event from the stream.
    enum ParsedEvent: Equatable {
        /// A text fragment of the assistant reply: `data: {"type":"delta","text":"…"}`.
        case delta(String)
        /// End of stream: `data: {"type":"done"}` or the bare `data: [DONE]` sentinel.
        case done
    }

    private var pendingLine = ""

    /// Feed one raw chunk of response body. Returns all events it completed, in order.
    mutating func feed(chunk: String) -> [ParsedEvent] {
        var events: [ParsedEvent] = []
        pendingLine += chunk

        // A line only counts once its terminator has arrived. Note: in a Swift
        // String, CRLF is a SINGLE grapheme cluster (one Character), so "\r\n"
        // must be matched as its own character — firstIndex(of: "\n") misses it.
        while let terminatorIndex = pendingLine.firstIndex(where: { $0 == "\n" || $0 == "\r\n" }) {
            let line = String(pendingLine[..<terminatorIndex])
            pendingLine = String(pendingLine[pendingLine.index(after: terminatorIndex)...])
            if let event = Self.parse(line: line) {
                events.append(event)
            }
        }
        return events
    }

    /// Parses one complete SSE line. Returns nil for blank separator lines,
    /// ": comment" heartbeats, non-data fields, and garbage — none are fatal.
    private static func parse(line rawLine: String) -> ParsedEvent? {
        var line = rawLine
        if line.hasSuffix("\r") { line.removeLast() } // tolerate CRLF endings

        guard !line.isEmpty, !line.hasPrefix(":") else { return nil }
        guard line.hasPrefix("data:") else { return nil }

        let payload = String(line.dropFirst("data:".count))
            .trimmingCharacters(in: .whitespaces)

        // Sentinel some SSE producers emit instead of a JSON done event.
        if payload == "[DONE]" { return .done }

        guard let payloadData = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let type = json["type"] as? String else {
            return nil // Unparseable data line — ignored by design.
        }

        switch type {
        case "delta":
            guard let text = json["text"] as? String else { return nil }
            return .delta(text)
        case "done":
            return .done
        default:
            return nil // Unknown event types are forward-compatible no-ops.
        }
    }
}

// MARK: - Errors

/// Typed failures of the worker chat client.
enum WorkerChatError: Error, LocalizedError {
    /// Transport-level failure (worker not running, connection refused/lost,
    /// timeout) that persisted after the single automatic retry.
    case connectionFailed(underlying: URLError)
    /// The worker answered with a non-2xx HTTP status.
    case serverError(statusCode: Int, body: String)
    /// The response was not an HTTP response at all.
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let underlying):
            return "Could not reach the worker at 127.0.0.1:8787 (\(underlying.localizedDescription))"
        case .serverError(let statusCode, let body):
            return "Worker error \(statusCode): \(body)"
        case .invalidResponse:
            return "Worker returned a non-HTTP response"
        }
    }
}

// MARK: - Client

/// Streams a chat reply from the local Cloudflare Worker proxy (`POST /chat`, SSE).
///
/// The app never talks to a provider directly — only to the worker's SSE shape
/// (decision D004). Time-box: 60s request timeout and exactly one retry on
/// connection failure, then a typed `WorkerChatError` (AGENTS.md root rule).
final class WorkerChatClient {

    static let defaultEndpoint = URL(string: "http://127.0.0.1:8787/chat")!

    private let endpoint: URL
    private let requestTimeout: TimeInterval

    init(endpoint: URL = WorkerChatClient.defaultEndpoint, requestTimeout: TimeInterval = 60) {
        self.endpoint = endpoint
        self.requestTimeout = requestTimeout
    }

    /// Sends the conversation to the worker and streams the reply.
    ///
    /// - Parameters:
    ///   - messages: full conversation, oldest first; roles are "user"/"assistant"/"system".
    ///   - screenshotBase64: raw base64 JPEG (no data-URI prefix) of the user's
    ///     frontmost display, or nil — sent as the `screenshot_base64` JSON field
    ///     (`null` when nil). See app/CHAT_CONTRACT.md.
    ///   - onDelta: called on the main actor with each NEW text fragment (not the
    ///     accumulated text), in arrival order — append it to what the UI shows.
    /// - Returns: the full accumulated reply text once the stream completes.
    /// - Throws: `WorkerChatError` for transport/HTTP failures (after one retry
    ///   on connection failure, and only when no delta has been delivered yet —
    ///   a retry after partial delivery would duplicate text in the UI).
    func streamReply(
        messages: [(role: String, content: String)],
        screenshotBase64: String? = nil,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        let progress = StreamProgress()
        do {
            return try await performStreamingRequest(
                messages: messages, screenshotBase64: screenshotBase64,
                onDelta: onDelta, progress: progress
            )
        } catch let error as URLError where Self.isConnectionFailure(error) {
            guard !progress.receivedAnyDelta else {
                throw WorkerChatError.connectionFailed(underlying: error)
            }
            // Exactly one retry, then a typed error.
            do {
                return try await performStreamingRequest(
                    messages: messages, screenshotBase64: screenshotBase64,
                    onDelta: onDelta, progress: progress
                )
            } catch let retryError as URLError {
                throw WorkerChatError.connectionFailed(underlying: retryError)
            }
        }
    }

    // MARK: Private

    /// Tracks whether any delta reached the UI, so a retry never replays text.
    private final class StreamProgress {
        var receivedAnyDelta = false
    }

    private func performStreamingRequest(
        messages: [(role: String, content: String)],
        screenshotBase64: String?,
        onDelta: @escaping @MainActor (String) -> Void,
        progress: StreamProgress
    ) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

        // Contract: screenshot_base64 always present — raw base64 JPEG or null (v1, D007).
        let body: [String: Any] = [
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "screenshot_base64": screenshotBase64.map { $0 as Any } ?? (NSNull() as Any)
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (byteStream, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WorkerChatError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            var errorBodyLines: [String] = []
            for try await line in byteStream.lines {
                errorBodyLines.append(line)
            }
            throw WorkerChatError.serverError(
                statusCode: httpResponse.statusCode,
                body: errorBodyLines.joined(separator: "\n")
            )
        }

        var parser = SSEEventParser()
        var accumulatedText = ""

        streamLoop: for try await line in byteStream.lines {
            // .lines strips the terminator; restore it so the parser sees complete lines.
            for event in parser.feed(chunk: line + "\n") {
                switch event {
                case .delta(let text):
                    progress.receivedAnyDelta = true
                    accumulatedText += text
                    await onDelta(text)
                case .done:
                    break streamLoop
                }
            }
        }
        return accumulatedText
    }

    /// Connection-level failures worth one retry (worker restarting, socket refused…).
    private static func isConnectionFailure(_ error: URLError) -> Bool {
        switch error.code {
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
             .networkConnectionLost, .notConnectedToInternet, .timedOut:
            return true
        default:
            return false
        }
    }
}
