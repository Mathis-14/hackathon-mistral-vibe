"use client"

import * as React from "react"
import { useEffect, useState } from "react"
const RenderTarget = {
    current: () => "preview",
    canvas: "canvas",
    export: "export",
    thumbnail: "thumbnail",
    preview: "preview",
}
import { motion, type AnimationOptions, type Variants } from "framer-motion"

/**
 * Typewriter — types out text one character at a time. Accepts an array
 * of strings; with multiple entries it types one, holds for `waitTime`,
 * deletes it, then types the next, looping when `loop` is true.
 *
 * Optional `prefix` renders as static text before the typed segment so
 * the component is drop-in for the "We're born to ___" pattern from the
 * source demo. Prefix and typed text can have separate colors.
 *
 * Implementation note — the typing state machine is a recursive
 * setTimeout chain driven by state transitions (currentIndex /
 * displayText / isDeleting / currentTextIndex), ported nearly verbatim
 * from the upstream fancycomponents.dev source. The chain is the
 * standard idiom for this effect; rewriting as an interval would lose
 * the per-phase delay differences (typing vs deleting vs waiting).
 *
 * On the static renderer (canvas / export) the timeout chain is
 * skipped and the first string is shown fully typed with the cursor
 * visible — a representative "completed phrase" snapshot.
 *
 * @framerSupportedLayoutWidth any
 * @framerSupportedLayoutHeight any
 * @framerIntrinsicWidth 600
 * @framerIntrinsicHeight 120
 */
export default function Typewriter(props: Partial<Props>) {
    props = { ...COMPONENT_DEFAULTS, ...props }
    const {
        texts,
        prefix,
        ease,
        deleteSpeed,
        showCursor,
        hideCursorOnType,
        cursorChar,
        cursorAnimationVariants: cursorAnimationVariantsProp,
        font,
        color,
        typedColor,
        cursorColor,
        style,
    } = props

    // Freeze ONLY on true static renders (export / thumbnail). The Framer
    // canvas and Preview run the live typing state machine so the effect plays
    // while editing. Gating on useIsStaticRenderer() (true on canvas) is what
    // previously froze it to the first string fully typed.
    const renderTarget = RenderTarget.current()
    const isStatic =
        renderTarget === RenderTarget.export ||
        renderTarget === RenderTarget.thumbnail
    // The cursor blink is a framer-motion animation, which does NOT run on the
    // Framer canvas — it would sit at the variant's initial opacity:0, so the
    // cursor vanishes. On the canvas render a plain (non-blinking) but visible
    // cursor; the live blink runs only in Preview.
    const isCanvas = renderTarget === RenderTarget.canvas

    // Timing comes from the `ease` Transition control (both in seconds; the
    // state machine runs in ms):
    //   duration → per-character type speed
    //   delay    → hold before a fully-typed word starts deleting
    // Delete speed is its own control, also in seconds.
    const typeDelayMs = Math.max(0, ((ease as any)?.duration ?? 0.07) * 1000)
    const holdMs = Math.max(0, ((ease as any)?.delay ?? 1.5) * 1000)
    const deleteDelayMs = Math.max(0, (deleteSpeed ?? 0) * 1000)

    // Normalize: filter out null/undefined entries so users with an
    // accidentally-empty Array slot don't crash the state machine.
    const list: string[] = (texts ?? []).filter(
        (t): t is string => typeof t === "string"
    )
    const hasTexts = list.length > 0

    const [displayText, setDisplayText] = useState("")
    const [currentIndex, setCurrentIndex] = useState(0)
    const [isDeleting, setIsDeleting] = useState(false)
    const [currentTextIndex, setCurrentTextIndex] = useState(0)

    // ---- Typing state machine -------------------------------------------
    // Ported from fancycomponents.dev/docs/components/text/typewriter.
    // Each render schedules ONE timeout for the next state transition;
    // the cleanup clears it on re-render or unmount. State changes drive
    // the next iteration via the dep array.
    useEffect(() => {
        if (isStatic) return
        if (!hasTexts) return

        let timeout: ReturnType<typeof setTimeout> | undefined

        const currentText = list[currentTextIndex] ?? ""

        const startTyping = () => {
            if (isDeleting) {
                if (displayText === "") {
                    setIsDeleting(false)
                    // Always loops — advance to the next string (wraps).
                    setCurrentTextIndex((prev) => (prev + 1) % list.length)
                    setCurrentIndex(0)
                    // Brief pause before the next string starts typing.
                    timeout = setTimeout(() => {}, holdMs)
                } else {
                    timeout = setTimeout(
                        () => setDisplayText((prev) => prev.slice(0, -1)),
                        deleteDelayMs
                    )
                }
            } else {
                if (currentIndex < currentText.length) {
                    timeout = setTimeout(() => {
                        setDisplayText(
                            (prev) => prev + currentText[currentIndex]
                        )
                        setCurrentIndex((prev) => prev + 1)
                    }, typeDelayMs)
                } else if (list.length > 1) {
                    // Finished typing this string; hold, then delete.
                    timeout = setTimeout(() => setIsDeleting(true), holdMs)
                }
                // Single string + finished typing → stay put.
            }
        }

        startTyping()

        return () => {
            if (timeout) clearTimeout(timeout)
        }
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [
        currentIndex,
        displayText,
        isDeleting,
        typeDelayMs,
        deleteDelayMs,
        holdMs,
        currentTextIndex,
        isStatic,
        hasTexts,
        // `list` intentionally excluded — it's rebuilt every render from
        // `texts`. Including it would re-run the effect each tick and
        // double-fire timeouts. The `texts` prop change reaches us via
        // the reset effect below.
    ])

    // If the `texts` prop changes (different array, different length,
    // different content), reset the state machine so we don't try to
    // index into a string that no longer exists.
    const textsKey = list.join("")
    useEffect(() => {
        setDisplayText("")
        setCurrentIndex(0)
        setIsDeleting(false)
        setCurrentTextIndex(0)
        // eslint-disable-next-line react-hooks/exhaustive-deps
    }, [textsKey])

    // ---- Cursor blink ----------------------------------------------------
    // Source's variants verbatim. duration:0.01 keeps the opacity jump
    // near-instant (block-cursor feel) while repeatDelay:0.4 controls
    // the visible-vs-hidden rhythm. repeatType:"reverse" makes each
    // cycle toggle between the initial (opacity 0) and animate (opacity 1)
    // states. Power-users can override with their own Variants via the
    // `cursorAnimationVariants` prop in TypeScript (not exposed in panel).
    const cursorAnimationVariants: Variants = cursorAnimationVariantsProp ?? {
        initial: { opacity: 0 },
        animate: {
            opacity: 1,
            transition: {
                duration: 0.01,
                repeat: Infinity,
                repeatDelay: 0.4,
                repeatType: "reverse",
            },
        },
    }

    // ---- Render ----------------------------------------------------------
    // Static renderer: show the first string fully typed with cursor
    // visible. Skip animation, skip the timeout chain.
    const renderedText = isStatic ? (list[0] ?? "") : displayText

    // hideCursorOnType: while actively typing OR deleting, suppress the
    // cursor. "Actively" means not at a settled boundary (empty pre-type
    // or fully typed and waiting). We check via state — if hasTexts is
    // false there's no animation, so cursor stays.
    const currentText = list[currentTextIndex] ?? ""
    const isActivelyTyping =
        !isStatic &&
        hasTexts &&
        (isDeleting || (currentIndex > 0 && currentIndex < currentText.length))
    const cursorHidden = hideCursorOnType && isActivelyTyping

    const cursorResolvedColor =
        cursorColor && cursorColor !== "" ? cursorColor : typedColor

    // Framer Font control returns a CSS-ready object (fontFamily, fontSize,
    // fontWeight, fontStyle, lineHeight, letterSpacing). Spread it onto the
    // text run; `letterSpacing: -0.025em` is a fallback the font overrides.
    const typeface = (font ?? {}) as Record<string, any>
    const fontCss = Object.fromEntries(
        Object.entries(typeface).filter(([k]) => k !== "textAlign")
    )

    return (
        <div
            style={{
                width: "100%",
                height: "100%",
                display: "flex",
                alignItems: "center",
                justifyContent: "flex-start",
                ...style,
            }}
        >
            <div
                style={{
                    display: "inline",
                    whiteSpace: "pre-wrap",
                    letterSpacing: "-0.025em",
                    ...fontCss,
                    color,
                }}
            >
                {prefix ? <span>{prefix}</span> : null}
                <span style={{ color: typedColor }}>{renderedText}</span>
                {showCursor &&
                    (isStatic || isCanvas ? (
                        <span
                            style={{
                                color: cursorResolvedColor,
                                marginLeft: "0.25rem",
                                visibility: cursorHidden ? "hidden" : "visible",
                            }}
                        >
                            {cursorChar}
                        </span>
                    ) : (
                        <motion.span
                            variants={cursorAnimationVariants}
                            initial="initial"
                            animate="animate"
                            style={{
                                color: cursorResolvedColor,
                                marginLeft: "0.25rem",
                                visibility: cursorHidden ? "hidden" : "visible",
                            }}
                        >
                            {cursorChar}
                        </motion.span>
                    ))}
            </div>
        </div>
    )
}

type Props = {
    texts: string[]
    prefix: string
    /** Typing transition. `duration` = per-char type speed; `delay` = hold
     *  before a fully-typed word starts deleting. */
    ease?: AnimationOptions
    deleteSpeed: number
    showCursor: boolean
    hideCursorOnType: boolean
    cursorChar: string
    /**
     * Power-user escape hatch — a full framer-motion `Variants` object
     * for the cursor blink. Not exposed in the property panel since
     * variants aren't serializable through Framer's controls. Override
     * programmatically when using this component as a React import.
     */
    cursorAnimationVariants?: Variants
    /** Framer Font control value — a CSS-ready typeface object. */
    font?: Record<string, any>
    color: string
    typedColor: string
    cursorColor: string
    style?: React.CSSProperties
}

const COMPONENT_DEFAULTS: Partial<Props> = {
    prefix: "",
    color: "#FFFFFF",
    texts: ["Interfaces", "Experiences", "Interactions", "Products"],
    typedColor: "#FFFFFF",
    ease: {
        type: "tween",
        duration: 0.07,
        delay: 1.5,
        ease: "easeInOut",
    },
    deleteSpeed: 0.1,
    showCursor: true,
    hideCursorOnType: false,
    cursorChar: "_",
    cursorColor: "",
    font: {
        fontFamily: "Inter",
        variant: "Regular",
        fontSize: 80,
        lineHeight: "1.4em",
        letterSpacing: "-0.025em",
    } as any,
}
