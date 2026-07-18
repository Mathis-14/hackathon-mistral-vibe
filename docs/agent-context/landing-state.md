# Landing — ship state

**Snapshot 2026-07-18 ~13:15 (hackathon day). Verify against `git log origin/main` before
trusting; this moves hourly.**

## Shipped

- PR #1 (`feat/landing-ui` → `main`, merged 12:59): full landing one-pager under
  `landing/`. Next 16 + Tailwind 4 + React 19; cream Mistral theme; OriginKit
  sticker-peel/swipe-stack/shiny-pill/typewriter; download CTA → `/VibeBuddy.dmg`.
- PR #3 (`feat/agentic` → `main`, merged 13:11): Mistral agentic worker (not landing).

## Locked decisions (user-confirmed, don't relitigate)

- Mood: ALL cream/light (deck welcome/prizes slides), not dark.
- Scope: hero-only one-pager; swipe-stack inside the hero; slim footer.
- Download: real file path `landing/public/VibeBuddy.dmg` + Vercel deploy.
- Branch used: `feat/landing-ui` (user overrode the wip/<name> convention for this track).
- Implementation: Next.js 16 one-pager with OriginKit components vendored as source under
  `landing/components/originkit/`; this keeps the UI independent of a component registry
  and adds no runtime dependencies beyond Framer Motion and Three.js.
- Why: judges reward product feel, while this parallel landing track must never gate the
  live demo.
- Timing warning: the kickoff deck says submissions are due at 18:00 with a demo video,
  earlier than the 19:30 feature freeze recorded in D011; Mathis arbitrates the timing.

## Open actions

1. **`assets-mistral/` is stranded**: PR #2 (`chore/assets`) merged into
   `feat/landing-ui` AFTER PR #1 had landed, so the 4 pixel GIFs (walking cat, robot,
   lechat) are on `origin/feat/landing-ui` but NOT on `main`. Fix: PR
   `feat/landing-ui` → `main` (only commits `898461e` + merge remain) or cherry-pick.
2. **Placeholder .dmg**: `landing/public/VibeBuddy.dmg` is a 77-byte text placeholder —
   replace with the signed artifact from the scaffold's `release.sh`.
3. **Deploy pending**: `npx vercel login` (interactive, user does it), then
   `cd landing && npx vercel --prod`.
4. **Phone check pending**: true <640px layout was never rendered (headless floor —
   see `originkit.md`); glance at the deployed URL on a phone.

## Commands

```bash
cd landing
npm install
npm run dev                  # local (session used port 3456: npm run dev -- --port 3456)
npx tsc --noEmit && npm run build   # the commit gate (AGENTS.md rule)
```

## Volatile lookups (never snapshot these)

- Current PRs: `gh pr list --state all`
- What's actually on main: `git fetch && git log --oneline origin/main | head`
- Is the .dmg still the placeholder: `wc -c landing/public/VibeBuddy.dmg` (77 bytes = yes)
