# OriginKit — vendoring recipe (verified 2026-07-18)

[originkit.dev](https://www.originkit.dev) is a free animated-component library (82
components). It is **NOT an npm package and NOT a shadcn registry** — you copy the TSX
source. Its MCP endpoint (`https://mcp.originkit.dev/mcp`) returned 401 unauthenticated;
the copy path below works without auth.

## Extraction recipe (no browser needed)

The full component source is embedded in each page's RSC flight payload as a `T` text
chunk. Fetch + decode:

```bash
curl -sL "https://www.originkit.dev/components/<name>" -o page.html
python3 - <<'EOF'
import re, json
html = open('page.html', encoding='utf-8').read()
chunks = re.findall(r'self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)', html)
data = ''.join(json.loads(c) for c in chunks).encode('utf-8')
srcs = []
for m in re.finditer(rb'([0-9a-f]+):T([0-9a-f]+),', data):  # id:T<hexlen>,<bytes>
    seg = data[m.end():m.end()+int(m.group(2),16)].decode('utf-8', 'replace')
    if 'export default' in seg or 'COMPONENT_DEFAULTS' in seg:
        srcs.append(seg)
open('src.tsx','w').write(max(srcs, key=len).replace('\r\n','\n'))
EOF
```

Fallback if extraction breaks: the site's "Copy Code" button in a real browser (pick the
`nextjs` stack in the playground).

## Integration rules (all learned the hard way)

- Components are inline-styled (zero Tailwind conflict) but ship WITHOUT `"use client"`
  — prepend it yourself; they all use hooks.
- WebGL components (sticker-peel, draggablesticker, dotmatrix) additionally need
  `next/dynamic` + `ssr: false` FROM A CLIENT WRAPPER (see `landing/components/HeroSticker.tsx`
  — `ssr:false` is illegal in server components in Next 16).
- Prop types are Framer-style with required fields but runtime defaults — change the
  signature to `Partial<Props>` and annotate `COMPONENT_DEFAULTS: Partial<Props>` or
  strict tsc fails on literal widening (e.g. framer-motion `Easing`).
- Deps: `framer-motion` for most, plus `three` (+`@types/three`) for WebGL ones. Nothing else.
- You own the pasted code — fork freely. `landing/components/originkit/SwipeStack.tsx`
  is already forked to render JSX children per card instead of `<img>`.

## Vendored inventory (`landing/components/originkit/`)

| File | Upstream | Notes |
|---|---|---|
| `StickerPeel.tsx` | sticker-peel | WebGL; `backColor` = peel-back tint (we use `#FA500F`) |
| `SwipeStack.tsx` | swipe-stack | FORKED: `cards: ReactNode[]` |
| `ShinyPill.tsx` | shiny-pill | zero-dep sheen text |
| `Typewriter.tsx` | typewriter | `ease.duration`=char speed, `ease.delay`=hold |

Shortlisted but unused (dark-oriented, clash with cream mood): electricborder, dotmatrix.
Full index lives on the originkit.dev homepage grid (there is NO /components index page).

## Headless-Chrome QA gotchas (macOS)

```bash
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
"$CHROME" --headless=new --user-data-dir=/tmp/prof-$$ --no-first-run \
  --use-angle=swiftshader --window-size=1440,900 --hide-scrollbars \
  --virtual-time-budget=12000 --screenshot=shot.png http://localhost:3000
```

- Without `--use-angle=swiftshader`, WebGL fails ("context lost" fallback) — NOT a real bug.
- Headless floors the window width at ~640px: a 390px `--window-size` renders a CROPPED
  640px layout. Don't diagnose mobile from it — check real breakpoints on a device.
- Always use a fresh `--user-data-dir`; a stale SingletonLock aborts the run.
