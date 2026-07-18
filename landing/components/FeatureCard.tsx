// A feature card styled like the deck's black "Track_01" slides:
// mono label with orange index, dashed separator, terse copy.
export default function FeatureCard({
  index,
  label,
  title,
  body,
}: {
  index: string;
  label: string;
  title: string;
  body: string;
}) {
  return (
    <div className="flex h-full w-full flex-col justify-between border border-[#2b2b35] bg-[#0b0b12] p-6 text-left">
      <p className="font-mono text-sm font-bold text-white">
        {label}
        <span className="text-accent">_{index}</span>
      </p>
      <div>
        <p
          className="font-mono text-[11px] tracking-widest text-[#5c5c6b]"
          aria-hidden="true"
        >
          {"– ".repeat(13)}
        </p>
        <h3 className="mt-4 font-mono text-2xl font-bold text-white">
          {title}
        </h3>
        <p className="mt-3 font-mono text-sm leading-relaxed text-[#a1a1ad]">
          {body}
        </p>
        <p
          className="mt-4 font-mono text-[11px] tracking-widest text-[#5c5c6b]"
          aria-hidden="true"
        >
          {"– ".repeat(13)}
        </p>
      </div>
      <div className="flex items-center gap-1" aria-hidden="true">
        {["#FFAF01", "#FF8204", "#FA500F", "#E61300", "#C4001D"].map((c) => (
          <span key={c} className="h-2 w-2" style={{ background: c }} />
        ))}
      </div>
    </div>
  );
}
