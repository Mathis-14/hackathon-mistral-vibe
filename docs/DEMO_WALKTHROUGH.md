# Vibe Buddy — video walkthrough (~2 min, shoot per beat, edit together)

Proposal from Edouard's side — Mathis owns the final cut (PRODUCT.md demo
script stays the reference; this is the shot-by-shot version with exact
lines and setup).

## Pre-flight (5 min, once)

- [ ] Do Not Disturb ON, personal notifications quiet, desktop clean
- [ ] `cd worker && npx wrangler dev` running, `curl 127.0.0.1:8787/health` says `"mode":"live"`
- [ ] App = latest (M icon in menu bar), permissions all green (no amber banner)
- [ ] demo-repo has its red test: `cd demo-repo && python3 -m pytest src/ -x` shows the failure (or just have `src/pricing.py` open with the bug visible)
- [ ] Mic input level checked in a 5s test recording; speak clearly, ~30cm
- [ ] Screen recording: ⇧⌘5, full screen, mic ON

## Beat 1 — The gap (10s) [Mathis]

Slide or slow pan over a real menu bar: ChatGPT icon, Claude icon…
**Line:** "Every menu bar has ChatGPT and Claude. Mistral wasn't there. We
built its place — this morning." Cut to our menu bar: **the M appears.**

## Beat 2 — Hey Vibe, hands-free (20s) — THE opener

Working in the editor, demo-repo bug on screen. Panel closed. Say, one
breath: **"Hey Vibe — why is this test failing?"**
On screen: panel slides in from the right · cat walks in "Listening…" →
"Transcribing with Voxtral…" · your words appear as a user bubble **with a
thumbnail of your screen** · Medium answers pointing at the actual bug.
**Line (voiceover):** "Voice in, screen-aware answers out. That was
Voxtral and Mistral Medium — live."

## Beat 3 — Actuation (15s)

Continue by voice (Ctrl+Option or Hey Vibe again):
**"Open Notes and start a fix checklist for me."**
On screen: overlay pill "Opening Notes…" + Notes opens.
**Line:** "It doesn't just answer — it acts. And never invisibly: every
action draws its trace."

## Beat 4 — Conduct Vibe Code agents (25s) — the Mistral-Vibe beat

Say: **"Hey Vibe — vibe, fix the failing pricing tests."**
On screen: confirmation bubble · VIBE CODE SESSIONS lights up, green dot,
live cost ticking · (optional cut) click the session → live transcript,
tool chips scrolling · agent finishes → **meow** + native notification.
**Line:** "Vibe Buddy conducts real Mistral Vibe Code agents — launched by
voice, watched live, cost included. When it's done, the cat tells you."

## Beat 5 — Routines (12s)

Clock button → routines tab → Run now on "Morning brief" → native alert.
**Line:** "Scheduled ambient agents, with native alerts."

## Beat 6 — It's a product (15s) [Mathis]

Landing page → Download → drag to Applications → the M in the menu bar.
**Line:** "Signed, downloadable today, built on the Vibe design language."

## Close (8s)

Panel visible, cat idle-out.
**Line:** "Vibe Buddy — Mistral, one keystroke away." Team card.

## Retake insurance

- Any beat can fall back to `DEMO_MODE=replay` (identical visuals)
- If a wake capture cuts too early: `defaults write com.vibebuddy.app vibebuddy.wakeSilenceSeconds -float 1.6`
- Backup: record beats 2-4 twice; keep the take where the cat is fully visible
