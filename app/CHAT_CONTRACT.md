# /chat contract — app ⇄ worker

> **DRAFT** — the canonical version lives in `worker/src/index.ts` (Mathis):
> adopt or amend, then change `SSEEventParser` (app) and the worker
> **in the same commit**, as per AGENTS.md.

## Request

`POST http://127.0.0.1:8787/chat` — `Content-Type: application/json`

```json
{ "messages": [{ "role": "user", "content": "..." }],
  "screenshot_base64": "/9j/4AAQSkZJRg..." }
```

- `role` is `"user" | "assistant" | "system"`; full conversation, oldest first.
- `screenshot_base64` is **always present** (v1, decision D007). Either:
  - a base64-encoded **JPEG** of the user's frontmost display (the one with the
    cursor), captured once at submit time, downscaled to **max 1280 px wide**,
    quality **0.6** — **raw base64, NO `data:image/jpeg;base64,` prefix**; or
  - `null` when the user opted out (`vibebuddy.includeScreenshot` UserDefault
    explicitly `false`), capture failed, or Screen Recording permission is
    missing. The worker must treat `null` as text-only chat.

## Response — SSE stream (`Content-Type: text/event-stream`)

Each event is one `data: <json>` line followed by a blank line:

```
data: {"type":"delta","text":"chunk of the reply"}
data: {"type":"done"}
```

- The client also tolerates a bare `data: [DONE]` sentinel as end-of-stream.
- `:` comment lines, blank lines, and unparseable `data:` lines are ignored (never fatal).
- Errors: non-2xx status with a plain-text body (no SSE framing).
- Client behavior: 60 s timeout, exactly one retry on connection failure, then replay fallback.
