"use client"

import type { CSSProperties } from "react"

interface ShinyPillProps {
    text: string
    link?: string
    textColor: string
    shineColor: string
    speed: number
    font: any
    style?: CSSProperties
}

const KEYFRAMES_ID = "shiny-pill-keyframes"

/**
 * Animated Shiny Text
 *
 * A line of text with a sheen that sweeps left-to-right on a loop.
 *
 * @framerIntrinsicWidth 240
 * @framerIntrinsicHeight 28
 *
 * @framerSupportedLayoutWidth auto
 * @framerSupportedLayoutHeight auto
 */
export default function ShinyPill(props: Partial<ShinyPillProps>) {
    props = { ...COMPONENT_DEFAULTS, ...props }
    const {
        text = "SHINY PILL",
        link,
        textColor = "#FFFFFF",
        shineColor = "#78FF83",
        speed = 1.5,
        font,
        style,
    } = props

    const isFixedWidth = style?.width === "100%"

    const shellStyle: CSSProperties = {
        ...style,
        position: "relative",
        display: "inline-flex",
        alignItems: "center",
        boxSizing: "border-box",
        ...(isFixedWidth ? {} : { minWidth: "max-content", width: "auto" }),
        whiteSpace: "nowrap",
        ...font,
    }

    const shineLayerStyle: CSSProperties = {
        position: "absolute",
        inset: 0,
        display: "flex",
        alignItems: "center",
        whiteSpace: "nowrap",
        color: shineColor,
        pointerEvents: "none",
        WebkitMaskImage:
            "linear-gradient(to right, transparent 30%, #000 50%, transparent 70%)",
        maskImage:
            "linear-gradient(to right, transparent 30%, #000 50%, transparent 70%)",
        WebkitMaskSize: "150% auto",
        maskSize: "150% auto",
        animation: `shinyPillSweep ${speed}s ease-in-out infinite`,
    }

    const content = (
        <div style={shellStyle}>
            <style
                id={KEYFRAMES_ID}
                dangerouslySetInnerHTML={{
                    __html: `@keyframes shinyPillSweep {
                        0% { -webkit-mask-position: 200%; mask-position: 200%; }
                        100% { -webkit-mask-position: -100%; mask-position: -100%; }
                    }`,
                }}
            />
            {/* Base layer — muted baseline color */}
            <span style={{ color: textColor }}>{text}</span>
            {/* Shine layer — bright copy masked by the sweeping gradient */}
            <span style={shineLayerStyle} aria-hidden="true">
                {text}
            </span>
        </div>
    )

    if (link) {
        return (
            <a
                href={link}
                style={{ textDecoration: "none", display: "inline-flex" }}
            >
                {content}
            </a>
        )
    }

    return content
}

const COMPONENT_DEFAULTS = {
    text: "SHINY PILL",
    textColor: "#FFFFFF",
    shineColor: "#78FF83",
    speed: 1.5,
    font: {
        fontFamily: "Inter",
        variant: "Bold",
        fontSize: "120px",
        letterSpacing: "-0.01em",
        lineHeight: "1em",
    } as any,
}
