# Session context snapshot — 2026-07-18 ~15:45 (hackathon day)

Restart brief for a fresh agent (any machine). Read order: `AGENTS.md` (rules, stack,
decision log D001–D019, verified API facts) → `PRODUCT.md` (pitch, MUSTs, demo script) →
`WORKER_BRIEF.md` (Edouard's handoff, app-side state) → `app/CHAT_CONTRACT.md` (the wire
shape the app actually speaks) → `docs/PLAN.md` (the approved work plan, Parts A/B/C) →
this file (what is true right now).

## Where the build stands (state-to-verify, dated 2026-07-18 ~15:00)

- Everything is merged into **`main`**: Edouard's full app (PR #5 — panel, fn+control
  hotkey, screenshot context, push-to-talk, `[OPEN_APP:]` actuation + overlay, routines,
  wake-word stretch, Vibe sessions strip; Xcode build green, 21/21 tests), the worker
  (PR #3), the landing page (PR #1).
- **Branch `feat/app-integration` — all three plan parts SHIPPED (user-authorized),
  Edouard takes over from here:**
  - Part A (b3e39ca): worker speaks the app's /chat wire shape (auto-detected by the
    `screenshot_base64` key; delta/done SSE out; legacy Anthropic shape kept). Replay
    AND live smokes GREEN including three new app-wire checks. **Live demo unblocked
    worker-side.**
  - Part B (d62f89b): `WorkerTranscriptionProvider.swift` (Voxtral via worker
    /transcribe, no auth) is now the factory default; Apple Speech fallback kept.
  - Part C (b5cd9a7): DesignSystem re-themed to the Vibe LIGHT look (value-only token
    flip; dark theme = revert of that commit).
- **NOT yet verified: the Xcode build.** This Mac has no Xcode — Parts B/C are only
  `swiftc -parse` syntax-checked. FIRST TASK for Edouard/the second Mac: build, run,
  eyeball the light theme (contrast on routines tab + overlay), test push-to-talk →
  Voxtral and the WORKER_BRIEF 2-minute live-chat test.
- Still open app-side (nice-to-have): `ActuationTokenParser` only parses `[OPEN_APP:]`;
  the model also emits `[OPEN_URL:]` (worker/CONTRACT.md).

## Machine notes

- Mathis's main Mac has NO Xcode (Command Line Tools only) — app dev happens on his
  SECOND Mac: install Xcode (App Store or developer.apple.com/download/all .xip),
  macOS-platform only, free Apple ID team, open `app/leanring-buddy.xcodeproj`,
  Signing & Capabilities → personal team, Cmd-R, re-grant Accessibility + Screen
  Recording + Microphone after rebuilds.
- Mistral API key: `.env` (repo root) and `worker/.dev.vars` — both gitignored, NEVER
  committed. On a new machine: copy `worker/.dev.vars.example` → `.dev.vars`, paste key.

## Bring the stack up / verify (copy-paste)

```bash
cd worker && npx wrangler dev          # http://127.0.0.1:8787 — exactly ONE instance
curl -s http://127.0.0.1:8787/health   # {"ok":true,"mode":"replay","model":"mistral-medium-3-5"}
bash scripts/smoke.sh                  # replay — after EVERY change
DEMO_MODE=live bash scripts/smoke.sh   # real API, costs credits, use sparingly
```

## Next steps (in order, per docs/PLAN.md)

1. **Part A — worker adopts the app wire shape** (detect `screenshot_base64` key; app
   framing out; replay in app framing; smoke.sh app-contract checks; update
   worker/CONTRACT.md). Unblocks the live demo. Worker-only, zero Swift changes.
2. E2E against the real app (WORKER_BRIEF "2-minute test").
3. **Part B — voice**: new `WorkerTranscriptionProvider.swift` → `127.0.0.1:8787/transcribe`,
   no auth; factory tries it first, Apple Speech fallback. Ping Edouard before touching app/.
4. **Part C — Vibe-light UI restyle** (DesignSystem.swift tokens → panel → components),
   user drives on the second Mac, agent guides. Never gates the demo.
5. Freeze 19:30 → fresh fixtures + backup video → rehearse ×2. Demo ~21:00.

## Hard rules that bit us today (respect them)

- The user gates EVERY commit; never on `main`; no AI/tool attribution in messages.
- Plan mode / "read-only" means exactly that — do not edit anything until the user
  says go, even obvious-looking fixes.
- Stay in your directories (D009); `app/` edits require flagging Edouard first.

## Maintenance rule

Update "Where the build stands" when a slice lands; append durable decisions to
AGENTS.md's decision log, not here. Delete stale state rather than letting it drift.
