# Vibe Buddy — Product

## Pitch (business angle)

- **Problem:** The desktop is where work happens, and Mistral isn't there. ChatGPT and Claude sit in the macOS menu bar, one keystroke from every workflow; Mistral users open a browser tab. For users that's friction; for Mistral it's the missing daily-habit surface — the ambient presence that makes an assistant the default.
- **Who it's for / who pays:** Every Mistral user on macOS from day one; Mistral itself is the natural home for the product (the desktop companion the Vibe lineup lacks).
- **Why now:** The Vibe rebrand (May 2026) unified chat, work, and code under one agent brand — but shipped web and mobile only. Desktop companions are the current battleground (ChatGPT and Claude desktop apps, the mid-2026 wave of scheduled ambient agents). The gap is open today and obvious to every judge in the room.
- **Why us / why this:** We've built this shape before — our scaffold is a hackathon-winning menu-bar companion (global modifier-only hotkey, screen context, streaming chat, key-safe proxy). We swap its engine to the Mistral API and push further than the incumbents: voice input via Voxtral, live Mac actuation, plus scheduled routines with native alerts.
- **Hero moment:** fn+control over any app → ask, spoken (Voxtral) or typed, with the screen as context → "open it and get me started" → the Mac obeys live, every action drawn on screen.
- What is real vs simulated: live = summon, voice transcription, streaming chat, screen context, actuation. Pre-baked = the routine's result (the scheduler is real; the demo alert is triggered manually because a cron can't fire on cue on stage).

## Event and judging

- Event: Mistral Vibe Hackathon, Paris, 2026-07-18 (8:30–21:00), Track 1 — "anything goes, showcase Mistral Vibe"; teams 1–4; prizes in Mistral credits; live demo at the end of the day.
- Judges reward: product-feel ("feels like a product, not a hackathon project"), Mistral-native showcase (their models, their brand, their missing surface), a demo moment that lands physically in the room.
- Judges penalize: generic assistant/RAG/chat-wrapper clichés, prototype-plus-video with nothing running, demos that showcase our old work instead of Mistral.

## The product at final stage (MUST — source of truth)

1. The product MUST be summonable from anywhere in macOS in under a second via the fn+control hotkey.
2. The product MUST answer with the user's current screen as context (screenshot captured at summon time).
3. The product MUST be able to act on the Mac — open apps and perform actions — with every action visibly surfaced on screen as it happens.
4. The product MUST run user-defined routines on a schedule and surface their results as native macOS alerts with the artifact one click away.
5. The product MUST keep all API keys server-side in the proxy; the desktop app never holds a secret.
6. The product MUST NEVER act invisibly — no actuation without an on-screen trace, no unattended action the user hasn't scheduled.
7. The product MUST take voice input via Voxtral (push-to-talk); typed input always remains available as the fallback.

## Demo script

1. The gap made visible: a slide of real menu bars — the ChatGPT icon, the Claude icon… and no M. "Mistral has no desktop presence. We built it this morning."
2. Working in a real app, press fn+control — the panel appears over the work; speak the question (Voxtral transcribes it live; typed input is the rehearsed fallback); the answer streams in with the screenshot visibly attached.
3. Hero: "open the app and get me started on X" — the app opens live, the overlay traces the action as it happens.
4. The menu-bar icon pulses: a routine finished — a native alert lands, its artifact (the morning brief) opens in the panel.
5. Close: "This is Vibe Buddy — Mistral, always one keystroke away. The desktop surface the Vibe family is missing."

## Scope decisions

- In for the demo: summon panel (fn+control), Voxtral voice input (push-to-talk), streaming chat, screenshot context, open-app actuation with on-screen trace, routines list UI + one pre-baked routine and its alert.
- In as a parallel track (never gates the live demo): landing page + downloadable signed .dmg — owned by Mathis on his second Mac.
- Out, said out loud: voice output/TTS, wake word ("Hey Vibe" — far stretch), MCP connector configuration UI, persistent memory, Windows/Linux, auto-update, onboarding.
- Pivot rule: if fn+control capture isn't proven by the end of v0, ship Ctrl+Option (already proven in the scaffold); if Mistral SSE streaming through the worker isn't proven by the end of v0, fall back to non-streamed full responses; if the Voxtral round-trip isn't proven by feature freeze (19:30), the demo uses typed input — the script survives all three.
