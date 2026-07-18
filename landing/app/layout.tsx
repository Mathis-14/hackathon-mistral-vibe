import type { Metadata } from "next";
import localFont from "next/font/local";
import { Inter, Space_Mono } from "next/font/google";
import "./globals.css";

const inter = Inter({
  variable: "--font-inter",
  subsets: ["latin"],
});

const spaceMono = Space_Mono({
  variable: "--font-space-mono",
  weight: ["400", "700"],
  subsets: ["latin"],
});

const altMistral = localFont({
  src: [
    {
      path: "../public/fonts/alt-mistral/ALTMistral-Regular.woff2",
      weight: "400",
      style: "normal",
    },
    {
      path: "../public/fonts/alt-mistral/ALTMistral-Medium.woff2",
      weight: "500",
      style: "normal",
    },
    {
      path: "../public/fonts/alt-mistral/ALTMistral-Semibold.woff2",
      weight: "600",
      style: "normal",
    },
  ],
  variable: "--font-alt-mistral",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Vibe Buddy — Mistral, one keystroke away.",
  description:
    "The macOS desktop companion for Mistral Vibe. Summon it over any app, speak to it, let it act on your Mac. Download the .dmg.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html
      lang="en"
      className={`${inter.variable} ${spaceMono.variable} ${altMistral.variable} h-full antialiased`}
    >
      <body className="min-h-full flex flex-col">{children}</body>
    </html>
  );
}
