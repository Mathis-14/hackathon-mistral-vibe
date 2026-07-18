//
//  BrandAssets.swift
//  leanring-buddy
//
//  Mistral brand primitives rendered natively: the official pixel-M
//  emblem (the exact 10 rects of mistral.ai's 2026 logo SVG, viewBox
//  21x15 — see docs/agent-context/mistral-design.md) and an
//  AppKit-backed animated GIF view for the walking-cat mascot, since
//  SwiftUI's Image does not animate GIFs.
//

import AppKit
import SwiftUI

// MARK: - Mistral Emblem

/// The official Mistral pixel emblem, drawn from the brand SVG's rects so
/// it stays crisp at any size. Intrinsic aspect ratio is 21:15.
struct MistralEmblemView: View {
    private struct Cell {
        let x: CGFloat
        let y: CGFloat
        let w: CGFloat
        let h: CGFloat
        let color: Color
    }

    private static let cells: [Cell] = [
        Cell(x: 3, y: 0, w: 3, h: 3, color: Color(hex: "#FFAF01")),
        Cell(x: 15, y: 0, w: 3, h: 3, color: Color(hex: "#FFAF01")),
        Cell(x: 3, y: 3, w: 6, h: 3, color: Color(hex: "#FF8204")),
        Cell(x: 12, y: 3, w: 6, h: 3, color: Color(hex: "#FF8204")),
        Cell(x: 3, y: 6, w: 15, h: 3, color: Color(hex: "#FA500F")),
        Cell(x: 3, y: 9, w: 3, h: 3, color: Color(hex: "#E61300")),
        Cell(x: 9, y: 9, w: 3, h: 3, color: Color(hex: "#E61300")),
        Cell(x: 15, y: 9, w: 3, h: 3, color: Color(hex: "#E61300")),
        Cell(x: 0, y: 12, w: 9, h: 3, color: Color(hex: "#C4001D")),
        Cell(x: 12, y: 12, w: 9, h: 3, color: Color(hex: "#C4001D")),
    ]

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width / 21, size.height / 15)
            let originX = (size.width - unit * 21) / 2
            let originY = (size.height - unit * 15) / 2
            for cell in Self.cells {
                // A hairline of bleed on each side hides antialiasing seams
                // between adjacent rows without visibly distorting the mark.
                let rect = CGRect(
                    x: originX + cell.x * unit,
                    y: originY + cell.y * unit,
                    width: cell.w * unit,
                    height: cell.h * unit
                ).insetBy(dx: -0.25, dy: -0.25)
                context.fill(Path(rect), with: .color(cell.color))
            }
        }
        .aspectRatio(21 / 15, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Animated GIF

/// AppKit-backed animated GIF view. Pass the bundled resource name
/// without the `.gif` extension.
struct AnimatedGIFView: NSViewRepresentable {
    let resourceName: String

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        if let url = Bundle.main.url(forResource: resourceName, withExtension: "gif") {
            imageView.image = NSImage(contentsOf: url)
        }
        // Let SwiftUI's .frame own the size instead of the image's
        // intrinsic 800x600.
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {}
}
