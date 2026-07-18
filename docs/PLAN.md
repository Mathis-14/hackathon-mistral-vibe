# Approved plan (2026-07-18) — integrate Edouard's pipeline + Voxtral voice + Vibe-light UI

STATUS 2026-07-18 ~15:45: Parts A, B, C shipped on `feat/app-integration`
(user-authorized). A is smoke-verified replay+live; B and C are syntax-checked only —
the Xcode build + visual pass + the E2E app test below are the remaining steps, on a
machine with Xcode (Edouard / second Mac).

## Part A — Worker speaks the app's /chat contract (worker/ + scripts/, no Swift)

Problem: `app/leanring-buddy/WorkerChatClient.swift` sends
`{"messages":[{role,content:string}], "screenshot_base64": <b64|null>}` and its
`SSEEventParser` understands only `data:{"type":"delta","text":…}` /
`data:{"type":"done"}` (bare `[DONE]` tolerated). The worker speaks the old
Anthropic-style shape. Fix worker-side only (D017): adopt the app shape as primary,
keep the anthropic shape for compat.

Changes in `worker/src/index.ts` (additive; two small uncommitted edits — header
comment + "narrow panel" prompt sentence — are part of this, keep them):

1. `handleChat`: body has a `screenshot_base64` key (app always sends it, even null,
   WorkerChatClient.swift:187-190) → app wire; else → existing anthropic wire.
2. `parseAppChatRequest` → normalize to the internal `AnthropicMessagesRequest`:
   roles user|assistant|system (system msgs merged into the `system` field — the
   existing ours-first merge in `anthropicToMistral` applies); non-null screenshot →
   image block (`media_type: image/jpeg`) attached to the LAST user message; app wire
   is always streaming.
3. Generalize `mistralStreamToAnthropic` → `mistralStreamToSSE(upstream, wire)`:
   app wire emits `data:{"type":"delta","text":…}\n\n` per chunk + final
   `data:{"type":"done"}\n\n`; anthropic wire byte-identical to today.
4. Replay: factor `fixtureFullText` → `fixtureDeltaChunks(fixture): string[]`; app-wire
   replay maps chunks to delta events + done, same 30 ms pacing, same fixture picker.
   Live-fallback path inherits this via `replayChat`.
5. `scripts/smoke.sh`: ADD app-contract checks (never weaken existing ones): app basic
   (`screenshot_base64:null` → delta events + done terminator + non-empty text), app
   screenshot (real b64), app actuation (trailing `[OPEN_APP:…]`).
6. Same change: update `worker/CONTRACT.md` (app shape = THE app contract; anthropic =
   compat/testing). `app/CHAT_CONTRACT.md` is Edouard's file — tell him it is adopted
   verbatim; do not edit it.

Verify: `cd worker && npx tsc --noEmit` → `bash scripts/smoke.sh` → once
`DEMO_MODE=live bash scripts/smoke.sh`.

## E2E against the real app (WORKER_BRIEF's 2-minute test)

wrangler dev running → launch the app (second Mac: Xcode Cmd-R) → type in the panel →
live streamed deltas render; "open Notes and get me started" → overlay + Notes opens.
This is the moment the live demo becomes real.

## Part B — Voice to Voxtral (app/, ~40 lines — PING EDOUARD FIRST)

Precondition: one team-chat message — "taking the /transcribe retarget + UI files in
app/, hold off there".

- New `app/leanring-buddy/WorkerTranscriptionProvider.swift`: clone of
  `OpenAIAudioTranscriptionProvider` (same WAV multipart from `BuddyWAVFileBuilder`)
  with URL `http://127.0.0.1:8787/transcribe`, NO auth header, `isConfigured` always
  true, displayName "Voxtral (worker)". Response decoder unchanged (worker returns the
  same `{"text":…}` shape).
- `BuddyTranscriptionProvider.swift` factory (line 36): try worker provider first,
  Apple Speech stays the on-device fallback.

Verify: push-to-talk → provider shows "Voxtral (worker)", transcript lands in input,
wrangler log shows the `/transcribe` hit.

## Part C — Vibe-light UI restyle (user drives on the second Mac, agent guides)

Target: Mistral Vibe web look — white/near-white bg (#FAFAF8), dark text, orange
#FF7000 accents, rounded pill input bar (+ leading, orange mic trailing), optional
"Suggested for you" rows when transcript is empty. Sacrificable at the 19:30 freeze;
dark theme = one git checkout away.

Only three files (rest is engine — don't touch):
1. `app/leanring-buddy/DesignSystem.swift` — flip the color/font tokens first (~80% of
   the look comes from here).
2. `app/leanring-buddy/VibeBuddyPanelView.swift` — input bar + header.
3. `app/leanring-buddy/VibeBuddyPanelComponents.swift` — light bubbles (white cards,
   subtle border), suggestion rows.

Each step: agent points at exact lines + explains (user is new to SwiftUI), user edits,
Cmd-R, iterate. Afterward: contrast check on overlay + routines tab (shared tokens),
full demo run-through; demo screenshots/backup video must be re-taken.

## Risks

- Concurrent app/ edits by Edouard's agent → Part B/C precondition ping is mandatory.
- Detection relies on `screenshot_base64` always present → confirmed in his client code.
- Late light theme → Part C explicitly droppable at freeze.
