/**
 * Vibe Buddy Proxy Worker
 *
 * Holds the Mistral API key so it never ships in the Mac app binary.
 * The Swift app talks ONLY to this Worker; the Worker fans out to
 * api.mistral.ai. No Anthropic API is ever called.
 *
 * /chat speaks TWO inbound wire shapes, auto-detected per request:
 *   app       — the shipped app's WorkerChatClient (app/CHAT_CONTRACT.md):
 *               {messages:[{role,content:string}], screenshot_base64} in,
 *               `data: {"type":"delta","text"}` / `{"type":"done"}` SSE out.
 *               Detected by the screenshot_base64 key (always present).
 *   anthropic — the scaffold's original Anthropic-Messages shape
 *               (`content_block_delta`/`text_delta` SSE out), kept for
 *               compat. See worker/CONTRACT.md.
 *
 * Routes:
 *   POST /chat        → Mistral chat completions (streamed or not).
 *                       Injects the action-grammar system prompt so the
 *                       model can end replies with [OPEN_APP:Name] /
 *                       [OPEN_URL:url] tokens the app parses.
 *   POST /transcribe  → Voxtral STT (multipart in, {"text": "..."} out)
 *   GET  /health      → {"ok":true, mode, model}
 *
 * DEMO_MODE=replay serves recorded SSE fixtures at realistic pacing so
 * the demo never depends on wifi or rate limits. In live mode every
 * upstream call is time-boxed (60s, one retry) and /chat falls through
 * to the fixture rather than hang. The `x-vibe-source` response header
 * says what actually served the request: live | replay | replay-fallback.
 */

import chatBasicFixture from "../../fixtures/chat-basic.sse";
import chatScreenshotFixture from "../../fixtures/chat-screenshot.sse";
import chatActuationFixture from "../../fixtures/chat-actuation.sse";
import transcriptFixture from "../../fixtures/transcript.json";

interface Env {
  MISTRAL_API_KEY?: string;
  MISTRAL_BASE_URL?: string;
  MISTRAL_CHAT_MODEL?: string;
  VOXTRAL_MODEL?: string;
  DEMO_MODE?: string;
}

const DEFAULT_BASE = "https://api.mistral.ai/v1";
const DEFAULT_CHAT_MODEL = "mistral-medium-3-5";
const DEFAULT_VOXTRAL_MODEL = "voxtral-mini-latest";
const UPSTREAM_TIMEOUT_MS = 60_000;
const REPLAY_EVENT_DELAY_MS = 30;

/**
 * The agentic layer's one behavioral lever. Lives here (not in Swift)
 * so prompt iteration never requires an app rebuild. The app may send
 * its own `system` string; both are forwarded (ours first).
 */
const ACTION_SYSTEM_PROMPT = `You are Vibe Buddy, a Mistral-powered macOS companion summoned over the user's current work with a hotkey. You usually receive a screenshot of the user's screen — ground your answer in what is actually visible. Be concise and concrete: short sentences, no filler. Your reply renders in a narrow floating panel — a few short sentences beat paragraphs.

You can act on the user's Mac with exactly two actions, triggered by ending your reply with ONE action token:
- [OPEN_APP:App Name] opens a macOS application. Use the exact application name, e.g. [OPEN_APP:Notes], [OPEN_APP:Google Chrome].
- [OPEN_URL:https://full.url] opens a link in the default browser. Always a complete absolute URL.

Hard rules for action tokens:
- At most ONE token per reply, and only when the user asked you to open/launch/start something.
- The token must be the VERY LAST thing in the reply — nothing after it, not even punctuation.
- Before the token, tell the user in one short sentence what you are doing, and include any content they asked for (an outline, a draft, a checklist) so it is on screen when the app opens.
- If the user did not ask for an action, do not emit any token.`;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    if (url.pathname === "/health" && request.method === "GET") {
      return withCors(
        jsonResponse({
          ok: true,
          mode: resolveMode(request, env),
          model: env.MISTRAL_CHAT_MODEL || DEFAULT_CHAT_MODEL,
        }),
      );
    }

    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    try {
      if (url.pathname === "/chat") return withCors(await handleChat(request, env));
      if (url.pathname === "/transcribe") return withCors(await handleTranscribe(request, env));
    } catch (error) {
      return errorResponse(url.pathname, error);
    }

    return new Response("Not found", { status: 404 });
  },
};

// ───────────────────────────────────────────────────────────────────
// Mode resolution: header override > env > replay-by-default
// ───────────────────────────────────────────────────────────────────
type DemoMode = "live" | "replay";

function resolveMode(request: Request, env: Env): DemoMode {
  const requested = (request.headers.get("x-demo-mode") || env.DEMO_MODE || "replay").toLowerCase();
  if (requested === "live") {
    if (env.MISTRAL_API_KEY) return "live";
    console.error("[mode] live requested but MISTRAL_API_KEY is missing — degrading to replay");
  }
  return "replay";
}

// ───────────────────────────────────────────────────────────────────
// /chat — scaffold-shaped in, Mistral upstream, scaffold SSE out
// ───────────────────────────────────────────────────────────────────
async function handleChat(request: Request, env: Env): Promise<Response> {
  const { wire, request: incoming, isStreaming } = parseChatRequest(await request.json());

  if (resolveMode(request, env) === "replay") {
    return replayChat(incoming, wire, isStreaming, "replay");
  }

  const baseURL = (env.MISTRAL_BASE_URL || DEFAULT_BASE).replace(/\/$/, "");
  const model = env.MISTRAL_CHAT_MODEL || DEFAULT_CHAT_MODEL;
  const mistralBody = anthropicToMistral(incoming, model, isStreaming);

  // Time-boxed, one retry. A hung call must not hang the demo.
  let upstream: Response | null = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      upstream = await fetch(`${baseURL}/chat/completions`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${env.MISTRAL_API_KEY}`,
          "content-type": "application/json",
        },
        body: JSON.stringify(mistralBody),
        signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
      });
      if (upstream.ok) break;
      console.error(`[/chat] upstream ${upstream.status} (attempt ${attempt + 1})`);
    } catch (error) {
      console.error(`[/chat] upstream failed (attempt ${attempt + 1}):`, error);
      upstream = null;
    }
  }

  if (!upstream || !upstream.ok || (isStreaming && !upstream.body)) {
    // Fall through to the fixture: a broken venue network serves the
    // recorded reply instead of an error dialog on stage.
    return replayChat(incoming, wire, isStreaming, "replay-fallback");
  }

  if (isStreaming && upstream.body) {
    return new Response(mistralStreamToSSE(upstream.body, wire), {
      status: 200,
      headers: {
        "content-type": "text/event-stream",
        "cache-control": "no-cache",
        "x-vibe-source": "live",
      },
    });
  }

  const completion = parseMistralChatCompletion(await upstream.json());
  return jsonResponse(anthropicMessage(completion.text, completion.finishReason), {
    "x-vibe-source": "live",
  });
}

// ───────────────────────────────────────────────────────────────────
// /transcribe — multipart WAV in, Voxtral upstream, {"text": ...} out
// ───────────────────────────────────────────────────────────────────
async function handleTranscribe(request: Request, env: Env): Promise<Response> {
  if (resolveMode(request, env) === "replay") {
    return jsonResponse({ text: transcriptFixture.text }, { "x-vibe-source": "replay" });
  }

  const incoming = await request.formData();
  // Older workers-types declarations omit File from FormData.get even
  // though multipart file parts are File objects at runtime. Widen to
  // unknown, then narrow with the platform runtime check.
  const file: unknown = incoming.get("file");
  if (!(file instanceof File)) {
    return jsonResponse({ error: "multipart field 'file' is required" }, {}, 400);
  }

  const upstream = new FormData();
  upstream.append("file", file, file.name || "audio.wav");
  upstream.append("model", env.VOXTRAL_MODEL || DEFAULT_VOXTRAL_MODEL);
  const language = incoming.get("language");
  if (typeof language === "string" && language.length > 0) {
    upstream.append("language", language);
  }

  const baseURL = (env.MISTRAL_BASE_URL || DEFAULT_BASE).replace(/\/$/, "");
  const response = await fetch(`${baseURL}/audio/transcriptions`, {
    method: "POST",
    headers: { authorization: `Bearer ${env.MISTRAL_API_KEY}` },
    body: upstream,
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });

  if (!response.ok) {
    // No fixture fallback here: a canned transcript of words the user
    // did not say is worse than surfacing the error — the app has its
    // own provider fallback chain.
    const errorBody = await response.text();
    console.error(`[/transcribe] Voxtral ${response.status}`);
    return new Response(errorBody, {
      status: response.status,
      headers: { "content-type": "application/json" },
    });
  }

  const transcript = parseVoxtralTranscript(await response.json());
  return jsonResponse({ text: transcript }, { "x-vibe-source": "live" });
}

// ───────────────────────────────────────────────────────────────────
// Replay: recorded SSE fixtures, served at realistic pace
// ───────────────────────────────────────────────────────────────────
function pickChatFixture(incoming: AnthropicMessagesRequest): string {
  if (anyContentBlockIsImage(incoming.messages)) return chatScreenshotFixture;
  const lastUserText = extractLastUserText(incoming).toLowerCase();
  if (/\b(open|launch|start|ouvre|lance)\b/.test(lastUserText)) return chatActuationFixture;
  return chatBasicFixture;
}

function replayChat(
  incoming: AnthropicMessagesRequest,
  wire: WireFormat,
  isStreaming: boolean,
  source: "replay" | "replay-fallback",
): Response {
  const fixture = pickChatFixture(incoming);

  if (!isStreaming) {
    return jsonResponse(anthropicMessage(fixtureFullText(fixture), "end_turn"), {
      "x-vibe-source": source,
    });
  }

  const encoder = new TextEncoder();
  // Fixtures are recorded in the anthropic framing; re-emit them in the
  // requested wire's framing so replay stays byte-identical to live.
  const events =
    wire === "app"
      ? [
          ...fixtureDeltaChunks(fixture).map(
            (text) => `data: ${JSON.stringify({ type: "delta", text })}`,
          ),
          `data: ${JSON.stringify({ type: "done" })}`,
        ]
      : fixture.split("\n\n").filter((event) => event.trim().length > 0);
  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      for (const event of events) {
        controller.enqueue(encoder.encode(`${event}\n\n`));
        await sleep(REPLAY_EVENT_DELAY_MS);
      }
      controller.close();
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "content-type": "text/event-stream",
      "cache-control": "no-cache",
      "x-vibe-source": source,
    },
  });
}

/** Extract the ordered text chunks from a fixture's text_delta events. */
function fixtureDeltaChunks(fixture: string): string[] {
  const chunks: string[] = [];
  for (const line of fixture.split("\n")) {
    if (!line.startsWith("data: ")) continue;
    try {
      const parsed = JSON.parse(line.slice("data: ".length)) as {
        type?: string;
        delta?: { type?: string; text?: string };
      };
      if (parsed.type === "content_block_delta" && parsed.delta?.type === "text_delta") {
        chunks.push(parsed.delta.text ?? "");
      }
    } catch {
      // Non-JSON data lines ([DONE]) are expected — skip.
    }
  }
  return chunks;
}

/** Reassemble the full reply text from a fixture's text_delta events. */
function fixtureFullText(fixture: string): string {
  return fixtureDeltaChunks(fixture).join("");
}

// ───────────────────────────────────────────────────────────────────
// Scaffold-shape ↔ Mistral translation primitives
// ───────────────────────────────────────────────────────────────────
interface AnthropicMessagesRequest {
  model?: string; // sent by the app, ignored: the worker owns model choice
  max_tokens?: number;
  stream?: boolean;
  system?: string;
  messages: Array<AnthropicMessage>;
}

interface AnthropicMessage {
  role: "user" | "assistant";
  content: string | Array<AnthropicContentBlock>;
}

type AnthropicContentBlock =
  | { type: "text"; text: string }
  | { type: "image"; source: { type: "base64"; media_type: string; data: string } };

interface ParsedMistralChatCompletion {
  text: string;
  finishReason: string;
}

class RequestValidationError extends Error {}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Which dialect the caller speaks. "app" is the shipped Swift client
 * (WorkerChatClient/SSEEventParser — app/CHAT_CONTRACT.md); "anthropic"
 * is the original scaffold shape, kept for smoke/curl compatibility.
 */
type WireFormat = "anthropic" | "app";

interface ParsedChatRequest {
  wire: WireFormat;
  request: AnthropicMessagesRequest;
  isStreaming: boolean;
}

function parseChatRequest(value: unknown): ParsedChatRequest {
  // The app's client always includes the screenshot_base64 key, even as
  // null (WorkerChatClient.swift) — that key IS the dialect marker.
  if (isRecord(value) && "screenshot_base64" in value) {
    return parseAppChatRequest(value);
  }
  const request = parseAnthropicMessagesRequest(value);
  return { wire: "anthropic", request, isStreaming: request.stream === true };
}

function parseAppChatRequest(value: Record<string, unknown>): ParsedChatRequest {
  if (!Array.isArray(value.messages)) {
    throw new RequestValidationError("Request must include a messages array");
  }
  const screenshot = value.screenshot_base64;
  if (screenshot !== null && typeof screenshot !== "string") {
    throw new RequestValidationError("screenshot_base64 must be a base64 string or null");
  }

  const systemParts: string[] = [];
  const messages: AnthropicMessage[] = [];
  for (const raw of value.messages) {
    if (!isRecord(raw) || typeof raw.content !== "string") {
      throw new RequestValidationError("Each message must have string content");
    }
    if (raw.role === "system") {
      systemParts.push(raw.content);
      continue;
    }
    if (raw.role !== "user" && raw.role !== "assistant") {
      throw new RequestValidationError("Each message must have a valid role");
    }
    messages.push({ role: raw.role, content: raw.content });
  }

  // The screenshot belongs to the CURRENT turn: attach it to the last
  // user message as an image block (the app captures JPEG, per contract).
  if (typeof screenshot === "string" && screenshot.length > 0) {
    for (let i = messages.length - 1; i >= 0; i--) {
      const message = messages[i];
      if (message.role !== "user" || typeof message.content !== "string") continue;
      messages[i] = {
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: screenshot } },
          { type: "text", text: message.content },
        ],
      };
      break;
    }
  }

  const request: AnthropicMessagesRequest = { messages };
  if (systemParts.length > 0) request.system = systemParts.join("\n\n");
  // The app's client only consumes SSE — this wire is always streamed.
  return { wire: "app", request, isStreaming: true };
}

function parseAnthropicMessagesRequest(value: unknown): AnthropicMessagesRequest {
  if (!isRecord(value) || !Array.isArray(value.messages)) {
    throw new RequestValidationError("Request must include a messages array");
  }

  const messages: AnthropicMessage[] = value.messages.map(parseAnthropicMessage);
  const parsed: AnthropicMessagesRequest = { messages };

  if (value.model !== undefined) {
    if (typeof value.model !== "string") throw new RequestValidationError("model must be a string");
    parsed.model = value.model;
  }
  if (value.max_tokens !== undefined) {
    if (
      typeof value.max_tokens !== "number" ||
      !Number.isInteger(value.max_tokens) ||
      value.max_tokens <= 0
    ) {
      throw new RequestValidationError("max_tokens must be a positive integer");
    }
    parsed.max_tokens = value.max_tokens;
  }
  if (value.stream !== undefined) {
    if (typeof value.stream !== "boolean") throw new RequestValidationError("stream must be a boolean");
    parsed.stream = value.stream;
  }
  if (value.system !== undefined) {
    if (typeof value.system !== "string") throw new RequestValidationError("system must be a string");
    parsed.system = value.system;
  }

  return parsed;
}

function parseAnthropicMessage(value: unknown): AnthropicMessage {
  if (!isRecord(value) || (value.role !== "user" && value.role !== "assistant")) {
    throw new RequestValidationError("Each message must have a valid role");
  }

  if (typeof value.content === "string") {
    return { role: value.role, content: value.content };
  }
  if (!Array.isArray(value.content)) {
    throw new RequestValidationError("Each message must have string or block-array content");
  }

  const content: AnthropicContentBlock[] = value.content.map(parseAnthropicContentBlock);
  return { role: value.role, content };
}

function parseAnthropicContentBlock(value: unknown): AnthropicContentBlock {
  if (!isRecord(value)) throw new RequestValidationError("Content blocks must be objects");

  if (value.type === "text" && typeof value.text === "string") {
    return { type: "text", text: value.text };
  }

  if (value.type === "image" && isRecord(value.source)) {
    const source = value.source;
    if (
      source.type === "base64" &&
      typeof source.media_type === "string" &&
      typeof source.data === "string"
    ) {
      return {
        type: "image",
        source: { type: "base64", media_type: source.media_type, data: source.data },
      };
    }
  }

  throw new RequestValidationError("Unsupported content block");
}

function parseMistralChatCompletion(value: unknown): ParsedMistralChatCompletion {
  if (!isRecord(value) || !Array.isArray(value.choices) || !isRecord(value.choices[0])) {
    throw new Error("Invalid Mistral chat completion schema");
  }

  const choice = value.choices[0];
  if (!isRecord(choice.message) || typeof choice.message.content !== "string") {
    throw new Error("Invalid Mistral chat message schema");
  }

  const finishReason =
    typeof choice.finish_reason === "string" ? choice.finish_reason : "end_turn";
  return { text: choice.message.content, finishReason };
}

function parseMistralTextDelta(value: unknown): string | null {
  if (!isRecord(value) || !Array.isArray(value.choices) || !isRecord(value.choices[0])) {
    throw new Error("Invalid Mistral stream chunk schema");
  }

  const delta = value.choices[0].delta;
  if (!isRecord(delta) || delta.content === null || delta.content === undefined) return null;
  if (typeof delta.content !== "string") throw new Error("Invalid Mistral text delta schema");
  return delta.content;
}

function parseVoxtralTranscript(value: unknown): string {
  if (!isRecord(value) || typeof value.text !== "string") {
    throw new Error("Invalid Voxtral transcription schema");
  }
  return value.text.trim();
}

function anyContentBlockIsImage(messages: AnthropicMessagesRequest["messages"]): boolean {
  return messages.some(
    (message) =>
      Array.isArray(message.content) && message.content.some((block) => block.type === "image"),
  );
}

function extractLastUserText(incoming: AnthropicMessagesRequest): string {
  for (let i = incoming.messages.length - 1; i >= 0; i--) {
    const message = incoming.messages[i];
    if (message.role !== "user") continue;
    if (typeof message.content === "string") return message.content;
    return message.content
      .filter((block): block is { type: "text"; text: string } => block.type === "text")
      .map((block) => block.text)
      .join(" ");
  }
  return "";
}

function anthropicToMistral(
  request: AnthropicMessagesRequest,
  model: string,
  isStreaming: boolean,
): Record<string, unknown> {
  const messages: Array<Record<string, unknown>> = [];

  const system = [ACTION_SYSTEM_PROMPT, request.system].filter(Boolean).join("\n\n");
  messages.push({ role: "system", content: system });

  for (const message of request.messages) {
    if (typeof message.content === "string") {
      messages.push({ role: message.role, content: message.content });
      continue;
    }
    // Anthropic image block → Mistral content part. Mistral accepts the
    // data-URI as a plain string in `image_url` (docs, checked 2026-07-18).
    const parts: Array<Record<string, unknown>> = [];
    for (const block of message.content) {
      if (block.type === "text") {
        parts.push({ type: "text", text: block.text });
      } else if (block.type === "image") {
        parts.push({
          type: "image_url",
          image_url: `data:${block.source.media_type};base64,${block.source.data}`,
        });
      }
    }
    messages.push({ role: message.role, content: parts });
  }

  return {
    model,
    max_tokens: request.max_tokens ?? 1024,
    stream: isStreaming,
    messages,
  };
}

function anthropicMessage(text: string, stopReason: string): Record<string, unknown> {
  return {
    id: `msg_${Date.now()}`,
    type: "message",
    role: "assistant",
    content: [{ type: "text", text }],
    stop_reason: stopReason,
  };
}

/**
 * Mistral chat-completions SSE → the wire's SSE dialect.
 * App wire: `data: {"type":"delta","text"}` per chunk, `{"type":"done"}`
 * at the end (what SSEEventParser in Swift consumes). Anthropic wire:
 * `content_block_delta` events with framing, ends by stream close.
 * Upstream `[DONE]` is consumed here either way.
 */
function mistralStreamToSSE(
  upstream: ReadableStream<Uint8Array>,
  wire: WireFormat,
): ReadableStream<Uint8Array> {
  const decoder = new TextDecoder();
  const encoder = new TextEncoder();

  const emit = (controller: ReadableStreamDefaultController<Uint8Array>, name: string, data: unknown) => {
    controller.enqueue(encoder.encode(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`));
  };
  const emitApp = (controller: ReadableStreamDefaultController<Uint8Array>, data: unknown) => {
    controller.enqueue(encoder.encode(`data: ${JSON.stringify(data)}\n\n`));
  };

  return new ReadableStream<Uint8Array>({
    async start(controller) {
      if (wire === "anthropic") {
        emit(controller, "message_start", {
          type: "message_start",
          message: { id: `msg_${Date.now()}`, type: "message", role: "assistant", content: [] },
        });
        emit(controller, "content_block_start", {
          type: "content_block_start",
          index: 0,
          content_block: { type: "text", text: "" },
        });
      }

      const reader = upstream.getReader();
      let buffer = "";
      try {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          buffer += decoder.decode(value, { stream: true });

          let separatorIndex: number;
          while ((separatorIndex = buffer.indexOf("\n\n")) !== -1) {
            const rawEvent = buffer.slice(0, separatorIndex);
            buffer = buffer.slice(separatorIndex + 2);

            for (const rawLine of rawEvent.split("\n")) {
              if (!rawLine.startsWith("data: ")) continue;
              const payload = rawLine.slice("data: ".length).trim();
              if (!payload || payload === "[DONE]") continue;
              try {
                const textChunk = parseMistralTextDelta(JSON.parse(payload));
                if (textChunk && textChunk.length > 0) {
                  if (wire === "app") {
                    emitApp(controller, { type: "delta", text: textChunk });
                  } else {
                    emit(controller, "content_block_delta", {
                      type: "content_block_delta",
                      index: 0,
                      delta: { type: "text_delta", text: textChunk },
                    });
                  }
                }
              } catch (parseError) {
                console.error("[/chat] unparseable upstream chunk", parseError);
              }
            }
          }
        }
      } finally {
        if (wire === "app") {
          emitApp(controller, { type: "done" });
        } else {
          emit(controller, "content_block_stop", { type: "content_block_stop", index: 0 });
          emit(controller, "message_stop", { type: "message_stop" });
        }
        controller.close();
      }
    },
  });
}

// ───────────────────────────────────────────────────────────────────
// Tiny utilities
// ───────────────────────────────────────────────────────────────────
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function jsonResponse(body: unknown, extraHeaders: Record<string, string> = {}, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...extraHeaders },
  });
}

function corsHeaders(): Record<string, string> {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET, POST, OPTIONS",
    "access-control-allow-headers": "content-type, authorization, x-api-key, x-demo-mode",
  };
}

function withCors(response: Response): Response {
  const merged = new Headers(response.headers);
  for (const [key, value] of Object.entries(corsHeaders())) {
    merged.set(key, value);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: merged,
  });
}

function errorResponse(path: string, error: unknown): Response {
  if (error instanceof RequestValidationError) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { "content-type": "application/json", ...corsHeaders() },
    });
  }

  console.error(`[${path}] unhandled error`, error instanceof Error ? error.name : "unknown");
  return new Response(JSON.stringify({ error: "Internal worker error" }), {
    status: 500,
    headers: { "content-type": "application/json", ...corsHeaders() },
  });
}
