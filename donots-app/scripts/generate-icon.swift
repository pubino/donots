#!/usr/bin/env swift
import AppKit
import Foundation

// MARK: - Icon Renderer

func renderIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    let s = size // shorthand for scaling
    let center = CGPoint(x: s / 2, y: s / 2)

    // --- Background: warm cream gradient filling the full canvas (squircle-ready) ---
    let bgColors = [
        CGColor(srgbRed: 1.0, green: 0.92, blue: 0.80, alpha: 1.0),
        CGColor(srgbRed: 0.98, green: 0.85, blue: 0.70, alpha: 1.0),
    ]
    let bgGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: bgColors as CFArray,
        locations: [0.0, 1.0]
    )!
    ctx.drawLinearGradient(
        bgGradient,
        start: CGPoint(x: 0, y: s),
        end: CGPoint(x: s, y: 0),
        options: []
    )

    // --- Donut body (dough) ---
    let outerR = s * 0.38
    let innerR = s * 0.145
    let donutCenter = CGPoint(x: center.x, y: center.y - s * 0.01)

    // Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.015), blur: s * 0.04,
                  color: CGColor(srgbRed: 0.3, green: 0.2, blue: 0.1, alpha: 0.35))

    // Dough color: golden-brown ring
    let doughColors = [
        CGColor(srgbRed: 0.85, green: 0.65, blue: 0.35, alpha: 1.0),
        CGColor(srgbRed: 0.78, green: 0.55, blue: 0.28, alpha: 1.0),
    ]
    let doughGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: doughColors as CFArray,
        locations: [0.0, 1.0]
    )!

    // Draw dough as outer circle minus inner circle
    let outerPath = CGMutablePath()
    outerPath.addEllipse(in: CGRect(
        x: donutCenter.x - outerR, y: donutCenter.y - outerR,
        width: outerR * 2, height: outerR * 2
    ))
    let innerPath = CGMutablePath()
    innerPath.addEllipse(in: CGRect(
        x: donutCenter.x - innerR, y: donutCenter.y - innerR,
        width: innerR * 2, height: innerR * 2
    ))

    ctx.addPath(outerPath)
    ctx.addPath(innerPath)
    ctx.clip(using: .evenOdd)

    ctx.drawLinearGradient(
        doughGradient,
        start: CGPoint(x: donutCenter.x, y: donutCenter.y + outerR),
        end: CGPoint(x: donutCenter.x, y: donutCenter.y - outerR),
        options: []
    )
    ctx.resetClip()
    ctx.restoreGState()

    // --- Frosting (top half, pink) ---
    // Frosting covers the top portion of the donut with a wavy bottom edge
    let frostingPath = CGMutablePath()
    let frostOuterR = outerR * 1.01
    let frostInnerR = innerR * 0.95

    // Build frosting shape: arc on top, wavy bottom
    let waveSegments = 16
    let startAngle = CGFloat.pi * 0.08
    let endAngle = CGFloat.pi * 0.92

    // Top outer arc (from right to left)
    frostingPath.addArc(
        center: donutCenter, radius: frostOuterR,
        startAngle: startAngle, endAngle: endAngle,
        clockwise: false
    )

    // Wavy transition along the bottom of frosting (left to right)
    for i in 0...waveSegments {
        let t = CGFloat(i) / CGFloat(waveSegments)
        let angle = endAngle + (2 * CGFloat.pi - endAngle + startAngle) * t
        let waveAmp = s * 0.018
        let waveFreq: CGFloat = 8
        let midR = (frostOuterR + frostInnerR) / 2
        let wave = sin(t * waveFreq * CGFloat.pi) * waveAmp
        let r: CGFloat
        if t < 0.15 || t > 0.85 {
            r = frostOuterR - (frostOuterR - frostInnerR) * min(t / 0.15, (1 - t) / 0.15)
        } else {
            r = midR + wave
        }
        let px = donutCenter.x + cos(angle) * r
        let py = donutCenter.y + sin(angle) * r
        if i == 0 {
            frostingPath.addLine(to: CGPoint(x: px, y: py))
        } else {
            frostingPath.addLine(to: CGPoint(x: px, y: py))
        }
    }

    // Inner arc back to start (right to left, reversed)
    frostingPath.addArc(
        center: donutCenter, radius: frostInnerR,
        startAngle: startAngle, endAngle: endAngle,
        clockwise: false
    )
    frostingPath.closeSubpath()

    // Clip to donut ring shape first
    ctx.saveGState()
    let clipOuter = CGMutablePath()
    clipOuter.addEllipse(in: CGRect(
        x: donutCenter.x - outerR, y: donutCenter.y - outerR,
        width: outerR * 2, height: outerR * 2
    ))
    let clipInner = CGMutablePath()
    clipInner.addEllipse(in: CGRect(
        x: donutCenter.x - innerR, y: donutCenter.y - innerR,
        width: innerR * 2, height: innerR * 2
    ))
    ctx.addPath(clipOuter)
    ctx.addPath(clipInner)
    ctx.clip(using: .evenOdd)

    // Draw frosting with gradient
    let frostColors = [
        CGColor(srgbRed: 0.95, green: 0.45, blue: 0.55, alpha: 1.0),
        CGColor(srgbRed: 0.90, green: 0.35, blue: 0.50, alpha: 1.0),
    ]
    let frostGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: frostColors as CFArray,
        locations: [0.0, 1.0]
    )!

    ctx.addPath(frostingPath)
    ctx.clip()
    ctx.drawLinearGradient(
        frostGradient,
        start: CGPoint(x: donutCenter.x, y: donutCenter.y + outerR),
        end: CGPoint(x: donutCenter.x, y: donutCenter.y - outerR * 0.2),
        options: []
    )
    ctx.resetClip()
    ctx.restoreGState()

    // --- Sprinkles ---
    struct Sprinkle {
        let angle: CGFloat // position on donut
        let radius: CGFloat // distance from donut center
        let rotation: CGFloat // sprinkle tilt
        let color: CGColor
        let lengthFactor: CGFloat
    }

    let sprinkleColors: [CGColor] = [
        CGColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.9),
        CGColor(srgbRed: 0.3, green: 0.8, blue: 0.9, alpha: 0.9),
        CGColor(srgbRed: 1.0, green: 0.85, blue: 0.2, alpha: 0.9),
        CGColor(srgbRed: 0.6, green: 0.9, blue: 0.4, alpha: 0.9),
        CGColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 0.9),
    ]

    // Place sprinkles on the frosted area (top half)
    let sprinkles: [Sprinkle] = [
        Sprinkle(angle: 0.20, radius: 0.30, rotation: 0.3, color: sprinkleColors[0], lengthFactor: 1.0),
        Sprinkle(angle: 0.32, radius: 0.26, rotation: -0.5, color: sprinkleColors[1], lengthFactor: 0.9),
        Sprinkle(angle: 0.45, radius: 0.33, rotation: 0.8, color: sprinkleColors[2], lengthFactor: 1.1),
        Sprinkle(angle: 0.55, radius: 0.22, rotation: -0.2, color: sprinkleColors[3], lengthFactor: 0.85),
        Sprinkle(angle: 0.65, radius: 0.35, rotation: 0.6, color: sprinkleColors[4], lengthFactor: 1.0),
        Sprinkle(angle: 0.75, radius: 0.28, rotation: -0.7, color: sprinkleColors[0], lengthFactor: 0.95),
        Sprinkle(angle: 0.38, radius: 0.36, rotation: 0.4, color: sprinkleColors[1], lengthFactor: 0.9),
        Sprinkle(angle: 0.58, radius: 0.30, rotation: -0.3, color: sprinkleColors[2], lengthFactor: 1.05),
        Sprinkle(angle: 0.82, radius: 0.32, rotation: 0.1, color: sprinkleColors[3], lengthFactor: 0.88),
        Sprinkle(angle: 0.25, radius: 0.35, rotation: -0.6, color: sprinkleColors[4], lengthFactor: 1.0),
        Sprinkle(angle: 0.50, radius: 0.26, rotation: 0.5, color: sprinkleColors[0], lengthFactor: 0.92),
        Sprinkle(angle: 0.70, radius: 0.24, rotation: -0.4, color: sprinkleColors[2], lengthFactor: 1.0),
    ]

    let sprinkleLen = s * 0.032
    let sprinkleWid = s * 0.010

    // Clip to donut ring for sprinkles too
    ctx.saveGState()
    ctx.addPath(clipOuter)
    ctx.addPath(clipInner)
    ctx.clip(using: .evenOdd)

    for sp in sprinkles {
        let a = sp.angle * CGFloat.pi * 2
        let r = sp.radius * s
        let px = donutCenter.x + cos(a) * r
        let py = donutCenter.y + sin(a) * r
        let len = sprinkleLen * sp.lengthFactor
        let rot = sp.rotation

        ctx.saveGState()
        ctx.translateBy(x: px, y: py)
        ctx.rotate(by: rot)

        let rect = CGRect(x: -len / 2, y: -sprinkleWid / 2, width: len, height: sprinkleWid)
        let roundedRect = CGPath(roundedRect: rect, cornerWidth: sprinkleWid / 2, cornerHeight: sprinkleWid / 2, transform: nil)
        ctx.setFillColor(sp.color)
        ctx.addPath(roundedRect)
        ctx.fillPath()

        ctx.restoreGState()
    }
    ctx.restoreGState()

    image.unlockFocus()
    return image
}

// MARK: - Icon Set Generation

let iconsetPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/Donots.iconset"

try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(name: String, px: Int)] = [
    ("icon_16x16", 16),
    ("icon_16x16@2x", 32),
    ("icon_32x32", 32),
    ("icon_32x32@2x", 64),
    ("icon_128x128", 128),
    ("icon_128x128@2x", 256),
    ("icon_256x256", 256),
    ("icon_256x256@2x", 512),
    ("icon_512x512", 512),
    ("icon_512x512@2x", 1024),
]

for entry in sizes {
    let image = renderIcon(size: CGFloat(entry.px))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fputs("Failed to render \(entry.name)\n", stderr)
        continue
    }
    let path = (iconsetPath as NSString).appendingPathComponent("\(entry.name).png")
    try png.write(to: URL(fileURLWithPath: path))
    print("Generated \(entry.name).png (\(entry.px)x\(entry.px))")
}

print("Iconset written to \(iconsetPath)")
