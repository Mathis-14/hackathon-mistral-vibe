# Vibe Buddy — Landing

One-page download site for the Vibe Buddy .dmg. Mistral 2026 primitives (warm paper, navy ink, flag gradient, Space Mono headlines) + OriginKit components (sticker-peel, swipe-stack fork, shiny-pill, typewriter — source copied per originkit.dev/integrations, inline-styled).

```bash
npm install
npm run dev        # http://localhost:3000
npm run build      # must be green before commit
```

- `public/VibeBuddy.dmg` is a placeholder — replace with the signed build from `release.sh`.
- `components/originkit/` is vendored third-party source; edit freely (SwipeStack is already forked to take JSX cards).
- Deploy: `vercel` from this directory.
