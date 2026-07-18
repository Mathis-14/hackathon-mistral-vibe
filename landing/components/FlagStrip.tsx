// The Mistral flag gradient — 5 stacked bars, hard stops, no blending.
const BARS = ["#FFAF01", "#FF8204", "#FA500F", "#E61300", "#C4001D"];

export default function FlagStrip({ barHeight = 4 }: { barHeight?: number }) {
  return (
    <div aria-hidden="true">
      {BARS.map((c) => (
        <div key={c} style={{ height: barHeight, background: c }} />
      ))}
    </div>
  );
}
