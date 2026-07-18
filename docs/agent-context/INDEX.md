# Agent context — index

Session-derived knowledge that is NOT inferable from the code. `AGENTS.md` stays the
normative source of truth; these files hold the reference material behind it.

| File | What it is | Read it when |
|---|---|---|
| `mistral-design.md` | Verified Mistral 2026 brand tokens, fonts, motifs, asset recipes | Touching any UI (landing or app re-theme) |
| `originkit.md` | How to vendor OriginKit components (extraction recipe + integration rules) | Adding/upgrading an animated component |
| `landing-state.md` | Dated ship state of `landing/` + pending actions | Resuming landing work or deploying |

## Maintenance rule

- `landing-state.md`: update the snapshot (and its date) every time a landing PR lands.
- The other files: append-only, when a fact is verified or a gotcha proves durable.
- Decisions themselves go to the `AGENTS.md` decision log (D0xx), not here.
- Never commit credentials, event passwords, or claim links here — this repo is public.
