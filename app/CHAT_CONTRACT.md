# Chat contract — SUPERSEDED

The canonical worker contract now lives in **`worker/CONTRACT.md`** (source:
`worker/src/index.ts`, per AGENTS.md). The app's `WorkerChatClient` and
`SSEEventParser` implement that shape: Anthropic-style request body (screenshot
as an image content block on the last user message), `content_block_delta`
SSE events, stream ends on close, trailing `[OPEN_APP:]` / `[OPEN_URL:]`
action tokens.

This file used to hold the app-side draft written before the worker existed;
it is kept only so old links don't dangle.
