# Vibe Buddy — Worker Contract (for the Swift app)

Worker runs at `http://127.0.0.1:8787` (`cd worker && npx wrangler dev`). All Mistral keys live here; the app never sends auth. Everything below is verified by `bash scripts/smoke.sh` (replay) and `DEMO_MODE=live bash scripts/smoke.sh` (real API) — both GREEN as of 2026-07-18 12:40.

**The streaming path is byte-compatible with the scaffold's `ClaudeAPI.swift`. If you keep that file, `/chat` works with ZERO changes** (the base URL is already `127.0.0.1:8787`, and the worker ignores the `model` field the app sends).

## POST /chat

Request — exactly what `ClaudeAPI.analyzeImageStreaming` already builds:

```json
{
  "model": "ignored-by-worker",
  "max_tokens": 1024,
  "stream": true,
  "system": "optional app-side system text (worker appends it to its own)",
  "messages": [
    { "role": "user", "content": "plain text" },
    { "role": "assistant", "content": "plain text" },
    { "role": "user", "content": [
        { "type": "image", "source": { "type": "base64", "media_type": "image/jpeg", "data": "<b64>" } },
        { "type": "text", "text": "Screen 1 (image dimensions: 1280x800 pixels)" },
        { "type": "text", "text": "the user's question" }
    ]}
  ]
}
```

Streaming response (`content-type: text/event-stream`): the only load-bearing event is

```
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"chunk"}}
```

Framing events (`message_start`, `content_block_start/stop`, `message_stop`) are emitted around it; the stream ends by closing (no `[DONE]` line — the scaffold parser handles both). Non-streaming (`"stream": false`) returns `{"content":[{"type":"text","text":"..."}], "stop_reason":"..."}`.

### Action tokens — WHAT YOU ADD (the only new Swift work on /chat)

The worker's system prompt makes the model end its reply with at most ONE action token when the user asked it to open something. Parse the **fully-accumulated** reply text (same pattern as the scaffold's `parsePointingCoordinates`):

```
\[OPEN_APP:([^\]]+)\]\s*$     → NSWorkspace.shared.open app by name (e.g. "Notes", "Google Chrome")
\[OPEN_URL:([^\]]+)\]\s*$     → NSWorkspace.shared.open(URL(string: $1)!)
```

Strip the token from the displayed/spoken text. Draw the overlay trace when executing — actuation must never be invisible. Live-measured reliability: 10/10 correct trailing tokens, 0/2 false positives on non-action prompts (2026-07-18).

## POST /transcribe  (Voxtral STT — replaces AssemblyAI/OpenAI providers)

Multipart form: `file` = 16 kHz mono PCM16 WAV (what `BuddyWAVFileBuilder` already produces; filename/mime `audio/wav`). Optional `language`. Any `model`/`response_format` fields are ignored (worker forces `voxtral-mini-latest`).

Response: `{ "text": "transcript" }` — same shape the scaffold's `TranscriptionResponse` decoder expects. So: clone `OpenAIAudioTranscriptionProvider`, point it at `http://127.0.0.1:8787/transcribe`, delete its Info.plist API key usage (send no auth), done.

## GET /health

`{"ok":true,"mode":"replay|live","model":"mistral-medium-3-5"}` — poke it when wiring up.

## Modes & demo safety

- `DEMO_MODE` env (worker/.dev.vars or wrangler.toml): `replay` (default — recorded fixtures, no network, no key) or `live`. A request header `x-demo-mode: live|replay` overrides per call — the app doesn't need to send it.
- In live mode every upstream call is time-boxed (60 s, one retry); `/chat` then falls back to the fixture instead of erroring. Response header `x-vibe-source: live|replay|replay-fallback` tells you what really served it.
- Replay fixtures stream at realistic pace and cover: plain answer, screenshot-grounded answer, actuation answer ending in `[OPEN_APP:Notes]` (auto-picked: image attached → screenshot fixture; "open/launch/ouvre/lance" in last user text → actuation fixture).

## Gotchas honored for you

- CORS `*`, `OPTIONS` → 204, `HEAD /` → 405 (your TLS warmup is fine), no inbound auth, streaming starts well inside your 120 s request timeout.
