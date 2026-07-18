"use client"

// Forked from OriginKit "Swipe Stack" (originkit.dev/components/swipe-stack):
// cards render arbitrary JSX children instead of <img> backgrounds.

import React, { useState } from "react"
import { motion, type Transition } from "framer-motion"

const PERSPECTIVE = 1000 // px
const DEPTH_SPACING = 10 // px

type SwipeStackProps = {
    cards: React.ReactNode[]
    cardWidth?: number
    cardHeight?: number
    cardRadius?: number // px
    swipeThreshold?: number
    tiltAngle?: number
    tiltAngleStart?: number
    xOffset?: number
    transition?: Transition
    style?: React.CSSProperties
}

export default function SwipeStack({
    cards: cardContents,
    cardWidth = 300,
    cardHeight = 400,
    cardRadius = 8,
    swipeThreshold = 50,
    tiltAngle = -45,
    tiltAngleStart = 0,
    xOffset = 10,
    transition = { type: "spring", stiffness: 300, damping: 30 },
    style,
}: SwipeStackProps) {
    const count = cardContents.length

    const [order, setOrder] = useState(() =>
        Array.from({ length: count }, (_, i) => i)
    )
    const [isPressed, setIsPressed] = useState(false)
    const [shouldReturnToCenter, setShouldReturnToCenter] = useState(false)

    React.useEffect(() => {
        setOrder((prev) =>
            prev.length === count
                ? prev
                : Array.from({ length: count }, (_, i) => i)
        )
    }, [count])

    const handleDragEnd = (info: { offset: { x: number; y: number } }) => {
        setIsPressed(false)
        const { offset } = info
        const distance = Math.sqrt(offset.x * offset.x + offset.y * offset.y)
        if (distance > swipeThreshold) {
            setOrder(([top, ...rest]) => [...rest, top])
        } else {
            setShouldReturnToCenter(true)
            setTimeout(() => setShouldReturnToCenter(false), 1000)
        }
    }

    const getCardStyle = (index: number) => {
        const stackOffset = index * 8
        const scaleValue = 1 - index * 0.05
        const rotationValue =
            count > 1
                ? tiltAngleStart +
                  (index / (count - 1)) * (tiltAngle - tiltAngleStart)
                : tiltAngleStart
        const xOffsetValue = count > 1 ? (index / (count - 1)) * xOffset : 0
        const isTopCard = index === 0
        const shouldReturn = isTopCard && shouldReturnToCenter

        return {
            zIndex: count - index,
            scale: scaleValue,
            x: shouldReturn ? 0 : xOffsetValue,
            y: shouldReturn ? 0 : -stackOffset,
            rotate: shouldReturn ? 0 : rotationValue,
            z: -index * DEPTH_SPACING,
            opacity: 1,
        }
    }

    return (
        <div
            style={{
                ...style,
                width: "100%",
                height: "100%",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                position: "relative",
                perspective: `${PERSPECTIVE}px`,
            }}
        >
            <div
                style={{
                    position: "relative",
                    width: cardWidth,
                    height: cardHeight,
                }}
            >
                {order.map((contentIndex, index) => {
                    const isTopCard = index === 0
                    const cardStyle = getCardStyle(index)

                    return (
                        <motion.div
                            key={contentIndex}
                            drag={isTopCard}
                            dragConstraints={{
                                left: 0,
                                right: 0,
                                top: 0,
                                bottom: 0,
                            }}
                            dragElastic={0.7}
                            dragMomentum={false}
                            dragTransition={{
                                bounceStiffness: 300,
                                bounceDamping: 20,
                            }}
                            onMouseDown={
                                isTopCard ? () => setIsPressed(true) : undefined
                            }
                            onMouseUp={
                                isTopCard ? () => setIsPressed(false) : undefined
                            }
                            onDragEnd={
                                isTopCard
                                    ? (_, info) => handleDragEnd(info)
                                    : undefined
                            }
                            animate={cardStyle}
                            transition={{
                                x: transition,
                                y: transition,
                                rotate: transition,
                                scale: transition,
                                zIndex: { duration: 0.3, ease: "easeOut" },
                                z: { duration: 0.3, ease: "easeOut" },
                            }}
                            initial={false}
                            whileDrag={{
                                scale: 1.05,
                                rotate: tiltAngleStart,
                                zIndex: 1000,
                            }}
                            style={{
                                position: "absolute",
                                width: "100%",
                                height: "100%",
                                borderRadius: cardRadius,
                                cursor: isTopCard
                                    ? isPressed
                                        ? "grabbing"
                                        : "grab"
                                    : "default",
                                userSelect: "none",
                                overflow: "hidden",
                            }}
                        >
                            {cardContents[contentIndex]}
                        </motion.div>
                    )
                })}
            </div>
        </div>
    )
}
