# Mistral 2026 design primitives — verified facts

Verified 2026-07-18 against live `mistral.ai` production CSS and the official `/brand`
page. The working tokens are implemented in `landing/app/globals.css` — this file keeps
the facts you can't read from our code.

## Tokens (implemented in `landing/app/globals.css`)

- Light "warm paper" bg `#FBFBF8` / `#F5F4EF`; ink is navy `#151524`, NOT black.
- Dark surfaces are navy `#151524` / `#242433` / `#343446`, NOT `#1a1a1a` — the app
  re-theme spec in AGENTS.md (`#1a1a1a` + `#FF7000`) predates this verification; prefer
  navy + `#FA500F` if the app side re-themes.
- Accent/CTA orange: `#FA500F` (hero brand orange), hover `#FF5229`.
- Flag gradient, top→bottom, HARD stops, never blended:
  `#FFAF01 → #FF8204 → #FA500F → #E61300 → #C4001D`
  (logo SVG uses `#E61300`; the CSS token red-600 is `#E51300` — use SVG values for the
  flag, token values for UI chrome).
- Hairline borders `#E4E3DE`; radius stays small (6–8px buttons/cards); no pill buttons.

## Typography

- Headings on mistral.ai: proprietary `ALTMistral` (clean grotesque, weight 500,
  tracking -0.02em). Do NOT self-host it (licensing) — substitute Inter Medium.
- Body: Inter. Eyebrow labels: Space Mono, 11–12px, uppercase — signature move.
- The kickoff deck uses MONO headlines — Space Mono is our sanctioned headline font.
- Both fonts are wired via `next/font/google` in `landing/app/layout.tsx`.

## Signature motifs (deck + site)

- Pixel emblem = abstract pixel cat/M. Official SVG vendored at
  `landing/components/Emblem.tsx` (10 paths, extracted verbatim from mistral.ai nav).
  Brand rule: prefer gradient version, monochrome on busy bg, never recolor.
- Pixel confetti corner bursts (deck welcome slide) → `landing/components/PixelConfetti.tsx`.
- Dashed `– – –` separators and `Track_01`-style underscore labels (deck track slides).
- Hairline-grid layout (1px dividers, bordered header cells), Swiss/technical feel.
- Buttons: solid near-black `#151524` fill, 6px radius, h-40/48, 13–14px medium text;
  ghost = 1px border + ~5% ink overlay.
- Copy voice: terse period-terminated declaratives ("Frontier AI. In your hands.").

## Asset recipes (fetch fresh, don't re-commit binaries already in repo)

```bash
# Animated pixel cat (already committed at landing/public/cat.gif)
curl -sL https://mistral.ai/images/cat/cat-sitting-black.gif -o cat.gif
# More pixel GIFs (walking cat, robot…) live in assets-mistral/ (see landing-state.md)
```

- Official brand kits (Cloudflare-gated — download in a real browser, not curl):
  `https://cms.globalaegis.net/api/documents/file/Mistral_Brandkit_2026.zip` and
  `Mistral_Logos_2026.zip`. Model icon SVGs: `https://mistral.ai/cms-media/api/media/file/icon-m-flower.svg` etc.
- `landing/public/sticker.png` (die-cut emblem sticker) was GENERATED — a pure-python
  PNG writer drawing the emblem's 10 rects at 28px/unit on a rounded 840×840 card.
  Regenerate by scaling the rect list in `landing/components/Emblem.tsx`.

## Context: the Vibe rebrand

Le Chat became **Vibe** on 2026-05-28 (chat/work/code under one brand, web+mobile only —
that gap is our pitch). Tagline: "Frontier AI. In your hands." Product page:
`mistral.ai/products/vibe`.
