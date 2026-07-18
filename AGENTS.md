# Vibe Buddy — Agent Guide

macOS menu-bar-only companion for Mistral: a global fn+control hotkey summons a floating panel over any app; the agent sees the screen, streams a Mistral reply through a key-holding Cloudflare Worker proxy, and can act on the Mac (open apps, with an on-screen trace). Product vision, pitch, and demo script live in `PRODUCT.md` — read it for any pitch, demo, or scope question; it is the source of truth for what the product must be.

**North star: a flawless live demo of summon → screen-aware answer → live actuation at ~21:00 today. Not on the demo path = not built today.**

In plan mode, run `/iterate-q` before locking the plan.

This file is the engineering source of truth: read it before any task, update it in the same change when a durable decision or constraint appears. When the plan changes, this file changes.

## Core flow (what the code implements)

```
fn+control (CGEvent listen-only tap, flagsChanged: .maskSecondaryFn + .maskControl) → panel summons (NSStatusItem + KeyablePanel)
Voice (core): push-to-talk mic → POST /transcribe (multipart) → Voxtral → transcript lands in the same input path as typed text
ScreenCaptureKit JPEG + user text → POST http://127.0.0.1:8787/chat (streaming SSE)
worker/src/index.ts translates to Mistral /v1/chat/completions (stream) → re-emits SSE → CompanionManager renders chunks
[OPEN_APP:Name] token parsed from the stream → NSWorkspace.shared.open + overlay trace (actuation has no other code path, by design)
Routines: in-app scheduler (JSON in UserDefaults) → same /chat path → UNUserNotificationCenter alert
```

## Stack — locked, do not re-litigate

| Layer | Choice |
|---|---|
| Desktop app | Swift 5 / SwiftUI menu-bar app (`LSUIElement`), Xcode 15+, macOS 14.2+ — scaffold: Xiexie/Clicky (MIT, attribution kept) |
| Proxy | Cloudflare Worker, plain TypeScript + wrangler — ALL API keys live in `worker/.dev.vars` only |
| Model/LLM | Mistral Medium 3.5 for ALL chat/agentic tasks (exact id verified hour 1, set in `worker/wrangler.toml` only; revisit only if it blocks); Voxtral (`voxtral-mini-latest`) for STT |
| Data | UserDefaults + JSON for routines — no DB |

## Commands

```bash
cd worker && npx wrangler dev      # proxy on http://127.0.0.1:8787 — run FIRST, keep open
bash scripts/smoke.sh              # THE demo-path smoke: /chat with image fixture + [OPEN_APP:] round-trip + /transcribe fixture — run after EVERY change
DEMO_MODE=live bash scripts/smoke.sh   # against the real Mistral API; costs credits, use sparingly
cd worker && npx tsc --noEmit      # must pass before every commit; app side: Xcode build green
# app: open the .xcodeproj, set the signing team, Cmd-R; re-grant permissions after rebuilds (see Runbook)
```

## Architecture

```
app/          # Swift sources — entry *App.swift; CompanionManager.swift = the state machine + stream/token parser
worker/src/   # index.ts — single fetch handler: /chat (translate + stream, DEMO_MODE switch) + /transcribe (Voxtral)
fixtures/     # recorded SSE replies, demo screenshots, transcript fixture, pre-baked routine artifact
landing/      # one-page download site + .dmg link (Mathis, second Mac — never gates the demo)
scripts/      # smoke.sh
```

- Dependencies point inward: `app → worker HTTP contract ← fixtures`. The Swift app never sees a provider format or an API key — only the worker's SSE shape.
- Parse at the boundary: every stream event and tool token goes through the one parser in CompanionManager before anything acts on it.
- Time-box every external call (LLM 60s, one retry), then fall through to the fixture. A hung call must not hang the demo.
- Make illegal states unrepresentable: actuation fires only from a parsed `[OPEN_APP:]` token inside an active session, and always draws its overlay — no silent path exists.
- Don't scaffold: no folders, seams, or abstractions the demo path doesn't need today.

## Mocks first (non-negotiable)

- The worker ships `DEMO_MODE=live|replay` (key absent → replay): replay serves recorded SSE fixtures byte-identical in shape to live, at realistic streaming pace. The demo can never die on venue wifi or a rate limit.
- Mock data must look REAL on screen: real app names, real artifact content.
- Fallback for the fallback: a pre-recorded screen video of the full demo, committed under `fixtures/`.

## External APIs — verified facts (checked 2026-07-18)

- FILL HOUR 1 FROM THE DOCS, NOT MEMORY — record here: exact Mistral Medium 3.5 model id + vision support, image-input format (base64 data URI vs URL), streaming SSE event shape, auth header, rate limits on hackathon credits. Docs: https://docs.mistral.ai
- Voxtral STT (CORE): `POST https://api.mistral.ai/v1/audio/transcriptions`, model `voxtral-mini-latest`, multipart — same shape as the scaffold's OpenAI STT provider (verify hour 1). Docs: https://docs.mistral.ai
- macOS facts: modifier-only hotkey needs the Accessibility permission; ScreenCaptureKit needs Screen Recording; both prompts reappear when the build signature changes.

## Build order

1. **v0 — two parallel tracks, shipped as fast as possible, ugly.** NO screenshot in v0 (moved to v1 by decision D007). Riskiest integrations first: Mistral streaming through the worker translator + fn+control capture.
   - *Edouard (app):* scaffold re-skinned, fn+control summon, one streamed text reply rendered end-to-end.
   - *Mathis (worker/agentic, standalone folder, plug-ready):* `/chat` (Mistral Medium 3.5, SSE translate + stream, DEMO_MODE replay) + `/transcribe` (Voxtral) + fixtures + smoke.sh — built and smoke-green independently, wired into the app the moment Edouard's panel is up. Voice is a MAIN feature, built now, not later.
2. **v1 — the full demo path**, every step covered by the smoke script: screenshot context, push-to-talk mic → `/transcribe` wired into the panel, `[OPEN_APP:]` actuation + overlay, routines panel + one native alert, Mistral re-theme of DesignSystem.swift (dark `#1a1a1a`, orange `#FF7000`).
3. **Parallel track (Mathis, second Mac), after the worker is plug-ready:** landing page + signed .dmg via the scaffold's `release.sh` — never gates the live demo.
4. **v2 — stretch, only after v1 is solid E2E:** "Hey Vibe" wake word, MCP client, `[POINT:x,y]` overlay reuse, icon polish.

Never fire a live routine on stage — the routine result and its alert are pre-baked in the afternoon; live = summon → (voice) → answer → actuation.
**Feature freeze 19:30** → fixtures/backup video → rehearse the script ×2, once from the .dmg install on the second Mac if it exists. Demo ~21:00.

## What never relaxes

- No secrets or PII in client code, commits, or logs — keys exist in `worker/.dev.vars` only.
- `npx tsc --noEmit` and the Xcode build pass before every commit.
- Every LLM/external response is schema-parsed before the code acts on it.
- The smoke script is never weakened to make it pass; every new demo step adds its check there.
- Search before building (`rg`) — the scaffold probably already does it.
- This file stays current.
- **Commit hygiene (hard rule):** commit messages NEVER contain `Co-Authored-By`, "Claude", or any AI/tool attribution — no exceptions.
- **Repo safety:** never commit on `main` — the agent works on a branch only; never commit without the user's go; never `push --force`, never rewrite history, never merge another branch without explicit approval. Review the diff (`git diff` + staged) before every commit — commit only what you intend. No destructive commands (`reset --hard`, branch deletion, `rm -rf`, dropping data) without explicit approval.

## Relaxed today (hackathon mode)

- Small increments on your working branch (`wip/<name>` — one per person, no PR ceremony). Never on `main`: `main` is the demo-safe line, and only the user merges into it when a slice is demo-ready. Propose each commit (diff summary + smoke green) and commit on the user's go; every commit stays smoke-green so `main` and every merged state are live rollback points.
- The smoke script IS the test suite. No unit-test ceremony off the demo path.
- No PR/review gate; ship and re-run the smoke.
- After any pipeline change: re-run the full flow and watch it. Do not assume previous results are still valid.
- Don't ask permission for what this file already grants: running smoke, small changes on the demo path — do them and report. Ask only when a rule in this file blocks you or the demo path itself is at stake.

## Team

| Area | Owner |
|---|---|
| `app/` (ALL Swift — engine + panel UI) | Edouard |
| `worker/` (agentic layer + orchestration) + `fixtures/` + `landing/` (+.dmg, on his second Mac) + PRODUCT/demo | Mathis |

- Stay in your directories; editing outside your area = shout in team chat first.
- The worker's SSE contract (`worker/src/index.ts`) is canonical — change it and CompanionManager's parser in the same commit.
- Runbook: exactly ONE `wrangler dev` instance across the team; re-grant Accessibility + Screen Recording after every rebuild; test the hotkey after every app relaunch.

## Decision log (append-only, Why first)

- D001 — Stack = Xiexie scaffold (Swift menu-bar app + TS Worker proxy). Why: proven hackathon-winning code the team owns; modifier hotkey, summonable panel, and streaming proxy already solved.
- D002 — Hero = summon + actuate live; routines pre-baked. Why: live actuation is the wow; a scheduler can't fire on cue on stage.
- D003 — Hotkey fn+control via `.maskSecondaryFn`, fallback Ctrl+Option. Why: the fallback is already proven in the scaffold — a zero-risk pivot.
- D004 — Every Mistral call goes through the worker. Why: keys never ship in the app; a provider/model swap stays a worker-only change.
- D005 — Product = Vibe Buddy; Edouard's Orchestral (fleet cockpit for parallel `vibe -p` agents) rejected. Why: the demo path is proven scaffold code and the desktop-gap story lands in one sentence; Orchestral's core interfaces (NDJSON shape, sessions dir) were unverified. Arbitrated by Mathis.
- D006 — Voice = MAIN feature via Voxtral, built during v0 in parallel (Mathis builds `/transcribe` + agentic calls standalone, plug-ready); typed input is the permanent fallback, voice-on-stage confirmed at rehearsal. Why: Mathis's arbitration; parallel build keeps it off Edouard's critical path.
- D007 — Screen capture moves to v1; v0 = summon + one streamed reply only. Why: shrink v0 to the two riskiest integrations. Arbitrated by Mathis.
- D008 — Model = Mistral Medium 3.5 for all tasks (exact id verified from docs hour 1); revisit only if it blocks. Why: one model everywhere = fewer variables today.
- D009 — Split: Edouard owns ALL of `app/` (Swift engine + UI); Mathis owns `worker/` agentic layer + `fixtures/` + landing page/.dmg (built on his second Mac) + PRODUCT/demo. Why: nobody shares an Xcode target; Mathis's tracks ship independently.
- D010 — Landing page + signed .dmg are IN as a Mathis parallel track that never gates the live demo. Why: product-feel win judges reward; notarization delays must not threaten 21:00.
- D011 — Feature freeze 19:30, then fixtures/backup video + rehearse ×2 (once from the .dmg install if it exists); demo ~21:00. Why: adopted from Edouard's plan, shifted to the real event schedule.

## Demo checklist (run before the demo)

- [ ] `bash scripts/smoke.sh` green on the demo machine, on venue wifi
- [ ] Voxtral round-trip tested in the actual room (noise) — go/no-go on voice live; typed fallback rehearsed either way
- [ ] `DEMO_MODE` set as intended; fixtures fresh and realistic
- [ ] Pre-baked routine artifact + alert in place; demo apps installed and logged in
- [ ] Rollback point known (last green commit: `git log --oneline -1`)
- [ ] Phone-hotspot fallback tested
- [ ] Pitch lands the hero moment (see `PRODUCT.md`)
