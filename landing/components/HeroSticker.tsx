"use client";

// StickerPeel is WebGL (Three.js) — client-only, no SSR.
import dynamic from "next/dynamic";

const StickerPeel = dynamic(() => import("./originkit/StickerPeel"), {
  ssr: false,
});

export default function HeroSticker({ size = 190 }: { size?: number }) {
  return (
    <div style={{ width: size, height: size }}>
      <StickerPeel
        image={{ src: "/sticker.png" }}
        imageWidth={size}
        imageHeight={size}
        hoverPeel={45}
        pressPeel={64}
        curlRotation={240}
        backColor="#FA500F"
        shadowEnabled
        shadow={{ opacity: 24, color: "#151524", x: -220, y: 120 }}
      />
    </div>
  );
}
