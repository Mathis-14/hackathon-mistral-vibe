# Brief for the worker-side agent — state of `wip/edouard` (2026-07-18 ~13:45)

You are building the `worker/` + `fixtures/` + `smoke.sh` track (AGENTS.md, Team
table, owner Mathis). The ENTIRE app side is built and pushed on `wip/edouard`
— pull it before doing anything. This file tells you exactly what exists, what
contract to satisfy, and what's left. AGENTS.md and PRODUCT.md remain the
sources of truth; read them first if you haven't.

## What is DONE on the app side (18 commits, Xcode build green, 21/21 unit tests)

Everything in the v0 + v1 build order, plus the v2 wake-word stretch:

- **Summon**: fn+control global hotkey (CGEvent listen-only tap, ctrl+option
  fallback per D003) toggles the panel from anywhere.
- **Panel**: Mistral-themed chat (dark #1A1A1A, orange #FF7000), streaming
  bubbles, auto-scroll, keyboard focus on open. `VibeBuddyPanelView.swift`.
- **Push-to-talk → chat**: the final transcript opens the panel and submits
  through the same pipeline as typed input. STT currently falls back to
  on-device Apple Speech (see "Remaining" #3 — Voxtral needs YOUR /transcribe).
- **Screenshot context** (MUST #2): captured once per submit, JPEG ≤1280px
  q0.6, raw base64, user message shows a "screen attached" badge. Sent as
  `screenshot_base64` (null when opted out / permission missing).
- **Actuation** (MUST #3/#6): every stream delta flows through
  `ActuationTokenParser`; `[OPEN_APP:Name]` → on-screen overlay pill trace
  (always, even if the open fails) → `NSWorkspace` open. Tokens split across
  SSE chunks are handled; 8 dedicated tests.
- **Routines** (MUST #4): panel tab, seeded "Morning brief", Run-now button →
  `UNUserNotificationCenter` alert. Runs through the same chat client.
- **Replay fallback**: without your worker the app streams a built-in fixture
  (includes one `[OPEN_APP:Notes]` — the full hero moment rehearses offline).
  Force it: `defaults write com.vibebuddy.app vibebuddy.chatMode replay`.
- **"Hey Vibe" wake word** (v2 stretch): custom openWakeWord model trained
  today (real-voice median score 0.66, 0/19 false triggers on adversarial
  decoys), Python sidecar in `app/wakeword/`, summons the panel.
- **Vibe Code sessions strip** (new decision D012, logged in AGENTS.md):
  read-only watcher over `~/.vibe/logs/session` shows live/recent Vibe Code
  CLI sessions (title, project, cost) in the panel.

## The contract YOUR worker must satisfy

Canonical draft: **`app/CHAT_CONTRACT.md`** (written from the app's actual
parser — if your shape must differ, DON'T diverge silently: per AGENTS.md the
worker and the app parser change in the same commit, so flag it to Edouard's
agent and we land it together).

**`POST http://127.0.0.1:8787/chat`** — request:
```json
{ "messages": [{"role": "user|assistant", "content": "…"}],
  "screenshot_base64": "<raw base64 JPEG, no data: prefix>" | null }
```
Response: `text/event-stream` with `data: {"type":"delta","text":"…"}` events,
terminated by `data: {"type":"done"}` (a bare `data: [DONE]` is tolerated;
comment/blank lines ignored; CRLF fine). App behavior: 60s timeout, exactly one
retry if zero deltas were delivered, then a visible error bubble.

**`POST /transcribe`** — multipart passthrough to Mistral
`/v1/audio/transcriptions`, model `voxtral-mini-latest` (shape verified live
this morning). This endpoint is what upgrades voice input from Apple Speech to
Voxtral (MUST #7).

**Your system prompt must** (a) use the screenshot when present, (b) emit
`[OPEN_APP:AppName]` (exact format, names may contain spaces, one token per
action) whenever the user asks to open/start something — the app executes and
traces them; there is no other actuation path. (c) Keep replies conversational
and short — they render in a 400px-wide panel.

**Model**: D008 says Mistral Medium 3.5 with the exact id to be verified from
https://docs.mistral.ai (never from memory) and set in `worker/wrangler.toml`
only. This verification is still OPEN — it's yours.

## How to test against the real app (2 minutes)

1. `cd worker && npx wrangler dev` (port 8787 — the app's hardcoded default).
2. Launch `~/Applications/VibeBuddy.app` (or Xcode Cmd-R from
   `app/leanring-buddy.xcodeproj`).
3. Type in the panel → your worker gets the request (with screenshot after the
   Screen Recording permission is granted). `delta`s must appear as they
   stream. Say something like "open Notes and get me started" to test the
   token path end-to-end.

## Remaining work, whole project (per AGENTS.md build order)

1. **`worker/` `/chat` + `/transcribe` + `fixtures/` + `scripts/smoke.sh` —
   YOU. The only missing piece between today's replay demo and the live
   Mistral demo.** Including DEMO_MODE=live|replay on your side.
2. Model id verification (D008, hour-1 item, still open — yours).
3. App-side, AFTER your `/transcribe` exists: retarget the STT provider from
   Apple Speech to the worker (Edouard's agent, ~20 min, flagged).
4. Landing `.dmg`: Edouard is configuring Developer ID signing in Xcode; his
   agent then adapts `app/scripts/release.sh` and hands you the real dmg for
   `landing/public/`.
5. 19:30 feature freeze → fresh fixtures + backup video → rehearse ×2
   (once from the .dmg install). Demo ~21:00.

## Ground rules reminders (AGENTS.md — they bit us today, respect them)

- Never commit on `main`; your branch is yours, only Edouard merges to main.
- No AI/tool attribution in commit messages, ever.
- `npx tsc --noEmit` green before every commit.
- Don't touch `app/` (D009) — if the contract needs an app change, say so.
