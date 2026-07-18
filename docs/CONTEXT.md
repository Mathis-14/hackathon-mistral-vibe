# Session context snapshot — 2026-07-18 ~12:55 (hackathon day)

Restart brief for a fresh agent. Read order: `AGENTS.md` (rules, stack, decision log
D001–D015, verified API facts) → `PRODUCT.md` (pitch, MUSTs, demo script) →
`worker/CONTRACT.md` (exact app↔worker contract) → this file (what exists right now).
Nothing here duplicates those files; this is state + pointers.

## Where the build stands (state-to-verify, dated 2026-07-18)

- Branch **`feat/agentic`**. The v0 agentic slice is committed in the same change as
  this snapshot: `worker/`, `fixtures/`, `scripts/`, `docs/`, `.gitignore`, and the
  AGENTS.md decision log/API facts update.
- The v0 agentic layer (Mathis's half) is **done and verified**:
  - `worker/src/index.ts` — `/chat` (Mistral streaming, scaffold-compatible SSE),
    `/transcribe` (Voxtral), `/health`, `DEMO_MODE` replay + live fallback.
  - `bash scripts/smoke.sh` GREEN (replay) and `DEMO_MODE=live bash scripts/smoke.sh`
    GREEN against the real API on `mistral-medium-3-5`. Reliability + tool_calls
    verification numbers: see AGENTS.md → External APIs.
- Edouard's remote **`origin/wip/edouard`** is at `53f1f72`: panel/hotkey, worker SSE
  chat, screenshot context, push-to-talk routing, `[OPEN_APP:]` actuation + overlay,
  routines/alerts, and the Mistral theme are present (recorded build green, 21/21
  tests). It is not merged into this branch. Remaining worker-contract gaps observed:
  voice still uses direct OpenAI or Apple Speech instead of `/transcribe`, and
  `[OPEN_URL:]` is not parsed.

## Bring the stack up / verify (copy-paste)

```bash
cd worker && npx wrangler dev          # serves http://127.0.0.1:8787 — keep open
curl -s http://127.0.0.1:8787/health   # {"ok":true,"mode":"replay","model":"mistral-medium-3-5"}
bash scripts/smoke.sh                  # replay — after EVERY change
DEMO_MODE=live bash scripts/smoke.sh   # real API, costs credits, use sparingly
```

A `wrangler dev` may already be running from the last session — check `/health` before
starting a second one (hard rule: exactly ONE instance, see AGENTS.md Runbook).

## Secrets (never commit, never restate)

- Mistral API key lives in `.env` (repo root) and `worker/.dev.vars` — both gitignored.
  To (re)create: copy `worker/.dev.vars.example` and paste the key from `.env`.
- Never commit: `.env`, `worker/.dev.vars`, `node_modules/`, `.wrangler/`.

## For the next commit/PR agent

- Commit rules are hard and live in AGENTS.md → "What never relaxes": no AI/tool
  attribution in messages, never on `main`, and the user gates every commit.
- The scaffold reference clone (Edouard's winning repo, MIT) sits in the session
  scratchpad only — it is a reference, not part of this repo.

## Next tracks (in priority order, per plan + arbitration)

1. Support Edouard's remaining `worker/CONTRACT.md` wiring, starting with the local
   Voxtral `/transcribe` provider; integrate branches only on the user's direction.
2. Mathis v1 items: routines pre-baked artifact + native-alert fixture; refresh
   `fixtures/screenshot.jpg` with a real capture (current one is synthetic — the
   terminal lacked Screen Recording permission).
3. Parallel track (never gates the demo): landing page + signed .dmg on Mathis's
   second Mac, via the scaffold's `release.sh`.
4. Stretch only after v1 E2E: see AGENTS.md Build order v2.

## Maintenance rule

Update the "Where the build stands" section when a slice lands or merges; append
durable decisions to AGENTS.md's decision log, not here. Delete this file's stale
state rather than letting it drift.
