import Image from "next/image";
import Emblem from "@/components/Emblem";
import FlagStrip from "@/components/FlagStrip";
import KeyCap from "@/components/KeyCap";
import PixelConfetti from "@/components/PixelConfetti";
import FeatureCard from "@/components/FeatureCard";
import HeroSticker from "@/components/HeroSticker";
import SwipeStack from "@/components/originkit/SwipeStack";
import Typewriter from "@/components/originkit/Typewriter";

const FEATURES = [
  {
    index: "01",
    label: "Voice",
    title: "Speak to it.",
    body: "Push-to-talk, transcribed live by Voxtral. Typed input always works.",
  },
  {
    index: "02",
    label: "Screen",
    title: "It sees your screen.",
    body: "Summoned over any app, your screen is the context — captured the moment you call it.",
  },
  {
    index: "03",
    label: "Action",
    title: "It acts on your Mac.",
    body: "Opens apps and gets you started. Every action is traced on screen as it happens.",
  },
  {
    index: "04",
    label: "Routine",
    title: "It works while you don't.",
    body: "Scheduled routines run on their own and land as native macOS alerts.",
  },
];

export default function Home() {
  return (
    <div className="relative flex min-h-screen flex-col overflow-hidden">
      <PixelConfetti corner="bottom-right" seed={23} />

      {/* Top strip — deck header pastiche */}
      <header className="relative z-10 flex items-center justify-between border-b border-hairline px-6 py-4 md:px-10">
        <div className="flex items-center gap-2.5">
          <Emblem size={26} />
          <span className="font-mono text-base font-bold">
            Vibe<span className="text-accent">_</span>Buddy
          </span>
        </div>
        <p className="hidden font-mono text-[11px] uppercase tracking-wider text-muted sm:block">
          Mistral Vibe Hackathon — Paris · July 18th 2026
        </p>
      </header>

      {/* Hero */}
      <main className="relative z-10 mx-auto flex w-full max-w-6xl flex-1 items-center px-6 py-16 md:px-10">
        <div className="grid w-full items-center gap-16 lg:grid-cols-[1.1fr_1fr]">
          {/* Left — headline + CTA */}
          <div>
            <h1 className="font-mistral text-4xl font-medium leading-[1.05] tracking-[-0.02em] sm:text-5xl md:text-6xl">
              Mistral.
              <br />
              One keystroke away.
            </h1>

            <div className="mt-6 h-8 md:h-9">
              <Typewriter
                prefix="It "
                texts={[
                  "speaks Voxtral.",
                  "sees your screen.",
                  "acts on your Mac.",
                  "runs your routines.",
                ]}
                color="#151524"
                typedColor="#FA500F"
                cursorColor="#FA500F"
                cursorChar="_"
                showCursor
                hideCursorOnType={false}
                deleteSpeed={0.03}
                ease={{ type: "tween", duration: 0.055, delay: 1.4 }}
                font={{
                  fontFamily: "var(--font-space-mono)",
                  fontSize: "22px",
                  fontWeight: 700,
                  lineHeight: "1.4em",
                }}
              />
            </div>

            <p className="mt-6 max-w-md text-base leading-relaxed text-muted">
              The desktop companion the Vibe family is missing. Vibe Buddy
              lives in your menu bar, summons over any app, and gets things
              done.
            </p>

            <div className="mt-10 flex flex-wrap items-center gap-5">
              <a
                href="/VibeBuddy.dmg"
                download
                className="inline-flex h-12 items-center gap-3 rounded-md bg-ink px-6 text-sm font-medium tracking-wide text-paper transition-colors hover:bg-accent"
              >
                <Emblem size={18} />
                Download for macOS
              </a>
              <p className="flex items-center gap-2 font-mono text-xs text-muted">
                then <KeyCap>fn</KeyCap>
                <span aria-hidden="true">+</span>
                <KeyCap>⌃</KeyCap> summons it anywhere
              </p>
            </div>
            <p className="mt-4 font-mono text-[11px] uppercase tracking-wider text-muted">
              macOS 14.2+ · Apple Silicon · Free
            </p>
          </div>

          {/* Right — swipeable feature deck + peelable sticker */}
          <div className="relative hidden justify-center lg:flex">
            <div className="h-[430px] w-[320px]">
              <SwipeStack
                cards={FEATURES.map((f) => (
                  <FeatureCard key={f.index} {...f} />
                ))}
                cardWidth={300}
                cardHeight={400}
                cardRadius={10}
                tiltAngle={-10}
                xOffset={36}
                swipeThreshold={50}
              />
            </div>
            <div className="absolute -right-10 -top-14">
              <HeroSticker size={170} />
            </div>
            <p className="absolute -bottom-6 left-1/2 -translate-x-1/2 font-mono text-[11px] uppercase tracking-wider text-muted">
              ← drag the cards →
            </p>
          </div>
        </div>
      </main>

      {/* Mobile feature deck */}
      <section className="relative z-10 px-6 pb-20 lg:hidden">
        <div className="mx-auto h-[430px] w-[300px]">
          <SwipeStack
            cards={FEATURES.map((f) => (
              <FeatureCard key={f.index} {...f} />
            ))}
            cardWidth={280}
            cardHeight={390}
            cardRadius={10}
            tiltAngle={-8}
            xOffset={20}
            swipeThreshold={50}
          />
        </div>
      </section>

      {/* Footer — cat on the hairline, flag strip */}
      <footer className="relative z-10">
        <div className="mx-auto flex max-w-6xl items-end justify-end px-6 md:px-10">
          <Image
            src="/cat.gif"
            alt="Mistral pixel cat"
            width={128}
            height={112}
            unoptimized
            className="mr-2 block h-14 w-16 object-cover object-top [image-rendering:pixelated]"
          />
        </div>
        <div className="border-t border-hairline py-3">
          <p className="text-center font-mono text-[11px] uppercase tracking-wider text-muted">
            Built at the Mistral Vibe Hackathon — Paris, July 18th 2026
          </p>
        </div>
        <FlagStrip barHeight={4} />
      </footer>
    </div>
  );
}
