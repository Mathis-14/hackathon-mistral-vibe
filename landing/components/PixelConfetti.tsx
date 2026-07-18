// Pixel-confetti bursts, like the corners of the deck's welcome slide.
// Deterministic layout (seeded PRNG) so server and client render identically.
const COLORS = ["#FFAF01", "#FF8204", "#FA500F", "#E61300", "#C4001D"];

function mulberry32(seed: number) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

type Corner = "top-left" | "top-right" | "bottom-left" | "bottom-right";

export default function PixelConfetti({
  corner,
  seed = 7,
  count = 26,
  spread = 190,
}: {
  corner: Corner;
  seed?: number;
  count?: number;
  spread?: number;
}) {
  const rand = mulberry32(seed);
  const squares = Array.from({ length: count }, (_, i) => {
    // Denser near the corner, thinning outward along a diagonal fan.
    const d = Math.sqrt(rand()) * spread;
    const angle = rand() * (Math.PI / 2);
    const size = rand() < 0.3 ? 8 : rand() < 0.6 ? 6 : 4;
    return {
      key: i,
      x: Math.cos(angle) * d,
      y: Math.sin(angle) * d,
      size,
      color: COLORS[Math.floor(rand() * COLORS.length)],
    };
  });

  const anchor: React.CSSProperties = {
    "top-left": { top: 0, left: 0 },
    "top-right": { top: 0, right: 0 },
    "bottom-left": { bottom: 0, left: 0 },
    "bottom-right": { bottom: 0, right: 0 },
  }[corner];
  const flipX = corner.endsWith("right") ? -1 : 1;
  const flipY = corner.startsWith("bottom") ? -1 : 1;

  return (
    <div
      aria-hidden="true"
      className="pointer-events-none absolute"
      style={{ ...anchor, width: spread, height: spread }}
    >
      {squares.map((s) => (
        <div
          key={s.key}
          className="absolute"
          style={{
            [flipX === 1 ? "left" : "right"]: s.x,
            [flipY === 1 ? "top" : "bottom"]: s.y,
            width: s.size,
            height: s.size,
            background: s.color,
          }}
        />
      ))}
    </div>
  );
}
