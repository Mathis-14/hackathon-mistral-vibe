export default function KeyCap({ children }: { children: React.ReactNode }) {
  return (
    <kbd className="inline-flex min-w-7 items-center justify-center rounded-md border border-hairline bg-paper-2 px-1.5 py-0.5 font-mono text-xs text-ink shadow-[0_1.5px_0_var(--hairline)]">
      {children}
    </kbd>
  );
}
