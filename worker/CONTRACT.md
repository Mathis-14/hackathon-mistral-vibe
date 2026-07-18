# Vibe Buddy — Worker Contract (for the Swift app)

Worker runs at `http://127.0.0.1:8787` (`cd worker && npx wrangler dev`). All Mistral keys live here; the app never sends auth. Everything below is verified by `bash scripts/smoke.sh` (replay) and `DEMO_MODE=live bash scripts/smoke.sh` (real API) — both GREEN as of 2026-07-18 ~15:30.

**The worker speaks the shipped app's contract (`app/CHAT_CONTRACT.md`) verbatim — `WorkerChatClient.swift` and `SSEEventParser` work with ZERO changes.** Dialect detection is per request: a body containing the `screenshot_base64` key (the app always sends it, even as `null`) gets the app dialect below; anything else gets the legacy Anthropic-style dialect (kept for smoke/curl compat, see git history of this file).

## POST /chat — app dialect (THE contract)

Request — exactly what `WorkerChatClient` builds:

```json
{ "messages": [{ "role": "user|assistant|system", "content": "plain text" }],
  "screenshot_base64": "<raw base64 JPEG, no data: prefix>"  }
```

- Full conversation, oldest first. `system` messages are merged into the worker's own system prompt (worker's first).
- `screenshot_base64` is `null` when the user opted out / capture failed — the worker treats that as text-only chat. When present it is attached to the LAST user message as image context for Mistral.

Response (`content-type: text/event-stream`), one `data:` line + blank line per event:

```
data: {"type":"delta","text":"chunk of the reply"}
data: {"type":"done"}
```

Always streamed. Errors: non-2xx with a plain-text body. Comment lines / unknown types are never sent but would be ignored by the parser anyway.

### Action tokens

The worker's system prompt makes the model end its reply with at most ONE action token when the user asked it to open something — parse on the fully-accumulated text:

```
\[OPEN_APP:([^\]]+)\]\s*$     → NSWorkspace open app by name ("Notes", "Google Chrome")
\[OPEN_URL:([^\]]+)\]\s*$     → NSWorkspace.shared.open(URL(string: $1)!)
```

Live-measured reliability on `mistral-medium-3-5`: 10/10 correct trailing tokens, 0/2 false positives (2026-07-18). `[OPEN_URL:]` is emitted by the model too — the app currently parses only `[OPEN_APP:]` (`ActuationTokenParser`); adding URL support is an app-side nicety, not a blocker.

## POST /transcribe  (Voxtral STT)

Multipart form: `file` = 16 kHz mono PCM16 WAV (what `BuddyWAVFileBuilder` produces; mime `audio/wav`). Optional `language`. Any `model`/`response_format` fields are ignored (worker forces `voxtral-mini-latest`). **No auth header.**

Response: `{ "text": "transcript" }` — same shape the existing `TranscriptionResponse` decoder expects. `WorkerTranscriptionProvider.swift` in the app targets this endpoint.

## GET /health

`{"ok":true,"mode":"replay|live","model":"mistral-medium-3-5"}` — poke it when wiring up.

## Modes & demo safety

- `DEMO_MODE` env (worker/.dev.vars or wrangler.toml): `replay` (default — recorded fixtures, no network, no key) or `live`. A request header `x-demo-mode: live|replay` overrides per call — the app doesn't need to send it.
- Replay serves the recorded fixtures re-framed in whichever dialect the caller spoke, at realistic pace: plain answer, screenshot-grounded answer, actuation answer ending in `[OPEN_APP:Notes]` (auto-picked: screenshot attached → screenshot fixture; "open/launch/ouvre/lance" in last user text → actuation fixture).
- In live mode every upstream call is time-boxed (60 s, one retry); `/chat` then falls back to the fixture instead of erroring. Response header `x-vibe-source: live|replay|replay-fallback` tells you what really served it. `/transcribe` surfaces upstream errors instead (a canned transcript of unsaid words is worse).

## Gotchas honored for you

- CORS `*`, `OPTIONS` → 204, `HEAD /` → 405, no inbound auth, streaming starts well inside the client's 60 s timeout.
