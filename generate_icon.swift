#!/usr/bin/env swift
/// Generates AzureGallery app icons (light / dark / tinted) at 1024×1024.
/// Usage: swift generate_icon.swift <output-directory>
import Foundation
import CoreGraphics
import ImageIO

// ── Canvas ──────────────────────────────────────────────────────────────────

let S: CGFloat = 1024

func makeContext() -> CGContext {
    let ctx = CGContext(
        data: nil, width: Int(S), height: Int(S),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Flip to y-down (top-left origin) — easier to reason about icon layout.
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

func savePNG(_ ctx: CGContext, _ path: String) {
    guard let img = ctx.makeImage() else { fatalError("makeImage failed") }
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dst = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
        fatalError("Cannot create destination at \(path)")
    }
    CGImageDestinationAddImage(dst, img, nil)
    CGImageDestinationFinalize(dst)
    print("✓ \(path)")
}

// ── Color helpers ────────────────────────────────────────────────────────────

let rgb = CGColorSpaceCreateDeviceRGB()

func col(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: rgb, components: [CGFloat(r)/255, CGFloat(g)/255, CGFloat(b)/255, a])!
}

func gray(_ v: CGFloat, _ a: CGFloat = 1) -> CGColor {
    let sp = CGColorSpaceCreateDeviceGray()
    return CGColor(colorSpace: sp, components: [v, a])!
}

// ── Cloud path ───────────────────────────────────────────────────────────────
//
//  Design: a wide cloud with 4 rounded bumps across the top.
//  cx / cy = center of the overall cloud shape (y-down).

func buildCloud(cx: CGFloat, cy: CGFloat) -> CGPath {
    let p = CGMutablePath()

    // Body — wide rounded rect forming the flat bottom of the cloud
    let bW: CGFloat = 590; let bH: CGFloat = 165
    p.addRoundedRect(
        in: CGRect(x: cx - bW/2, y: cy - bH*0.35, width: bW, height: bH),
        cornerWidth: bH/2, cornerHeight: bH/2
    )

    // Bump helper (y-down: smaller dy = higher on screen)
    func bump(_ dx: CGFloat, _ dy: CGFloat, _ r: CGFloat) {
        p.addEllipse(in: CGRect(x: cx+dx-r, y: cy+dy-r, width: r*2, height: r*2))
    }

    // Four overlapping bumps — spacing chosen so adjacent bumps always intersect
    bump(-235, -55,  118)   // far-left
    bump( -75, -110, 152)   // left-center
    bump( +90, -110, 148)   // right-center
    bump(+250, -52,  115)   // far-right

    return p
}

// ── Landscape (clipped inside cloud) ────────────────────────────────────────

func drawLandscape(_ ctx: CGContext, cx: CGFloat, cy: CGFloat, mountainColor: CGColor) {
    ctx.setFillColor(mountainColor)

    // Ground strip
    ctx.fill(CGRect(x: cx - 320, y: cy + 72, width: 640, height: 120))

    // Sun (upper-left)
    ctx.fillEllipse(in: CGRect(x: cx - 272, y: cy - 92, width: 86, height: 86))

    // Left mountain
    let m1 = CGMutablePath()
    m1.move(to:    CGPoint(x: cx - 300, y: cy + 72))
    m1.addLine(to: CGPoint(x: cx - 95,  y: cy - 78))
    m1.addLine(to: CGPoint(x: cx + 80,  y: cy + 72))
    m1.closeSubpath()
    ctx.addPath(m1); ctx.fillPath()

    // Right mountain (taller)
    let m2 = CGMutablePath()
    m2.move(to:    CGPoint(x: cx + 5,   y: cy + 72))
    m2.addLine(to: CGPoint(x: cx + 210, y: cy - 100))
    m2.addLine(to: CGPoint(x: cx + 415, y: cy + 72))
    m2.closeSubpath()
    ctx.addPath(m2); ctx.fillPath()

    // Snow caps
    ctx.setFillColor(col(255, 255, 255, 0.88))

    let s1 = CGMutablePath()
    s1.move(to:    CGPoint(x: cx - 95,  y: cy - 78))
    s1.addLine(to: CGPoint(x: cx - 62,  y: cy - 28))
    s1.addLine(to: CGPoint(x: cx - 128, y: cy - 28))
    s1.closeSubpath()
    ctx.addPath(s1); ctx.fillPath()

    let s2 = CGMutablePath()
    s2.move(to:    CGPoint(x: cx + 210, y: cy - 100))
    s2.addLine(to: CGPoint(x: cx + 248, y: cy - 40))
    s2.addLine(to: CGPoint(x: cx + 172, y: cy - 40))
    s2.closeSubpath()
    ctx.addPath(s2); ctx.fillPath()
}

// ── Icon variants ─────────────────────────────────────────────────────────────

enum Variant { case light, dark, tinted }

func drawIcon(variant: Variant) -> CGContext {
    let ctx = makeContext()
    let cx = S / 2
    let cy = S / 2 - 10   // slightly above center

    // Background gradient
    switch variant {
    case .light:
        let g = CGGradient(colorsSpace: rgb,
            colors: [col(20, 142, 228), col(0, 56, 110)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g,
            start: CGPoint(x: cx * 0.4, y: 0), end: CGPoint(x: cx * 1.6, y: S), options: [])

    case .dark:
        let g = CGGradient(colorsSpace: rgb,
            colors: [col(8, 72, 130), col(2, 18, 55)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g,
            start: CGPoint(x: 0, y: 0), end: CGPoint(x: S, y: S), options: [])

    case .tinted:
        // Neutral gray — iOS replaces the background color when user picks a tint.
        ctx.setFillColor(gray(0.45))
        ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    }

    // Radial highlight for depth (light & dark only)
    if variant != .tinted {
        let sp = CGColorSpaceCreateDeviceRGB()
        let hl = CGGradient(colorsSpace: sp,
            colors: [col(255,255,255, 0.13), col(255,255,255, 0)] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(hl,
            startCenter: CGPoint(x: cx, y: S * 0.28), startRadius: 0,
            endCenter:   CGPoint(x: cx, y: S * 0.28), endRadius: S * 0.62,
            options: [])
    }

    let cloud = buildCloud(cx: cx, cy: cy)

    // Drop shadow behind cloud
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 38, color: col(0, 0, 0, 0.22))
    ctx.setFillColor(col(255, 255, 255))   // shadow caster color (invisible, shadow only shown)
    ctx.addPath(cloud); ctx.fillPath()
    ctx.restoreGState()

    // Cloud fill
    let cloudColor: CGColor = variant == .tinted ? gray(0.97) : col(255, 255, 255, 0.97)
    ctx.setFillColor(cloudColor)
    ctx.addPath(cloud); ctx.fillPath()

    // Landscape clipped to cloud
    ctx.saveGState()
    ctx.addPath(cloud); ctx.clip()
    let mountainColor: CGColor
    switch variant {
    case .light:   mountainColor = col(0, 82, 155, 0.92)
    case .dark:    mountainColor = col(0, 55, 110, 0.94)
    case .tinted:  mountainColor = gray(0.38)
    }
    drawLandscape(ctx, cx: cx, cy: cy, mountainColor: mountainColor)
    ctx.restoreGState()

    return ctx
}

// ── Main ──────────────────────────────────────────────────────────────────────

let outDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath

savePNG(drawIcon(variant: .light),  "\(outDir)/AppIcon.png")
savePNG(drawIcon(variant: .dark),   "\(outDir)/AppIcon-dark.png")
savePNG(drawIcon(variant: .tinted), "\(outDir)/AppIcon-tinted.png")
