// Generates the placeholder Cookie app icon (1024×1024 PNG).
// Stand-in artwork only — replaced with the final illustration later.
// Usage: swift scripts/make_icon.swift <output.png>

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let canvas = 1024

let ctx = CGContext(
    data: nil,
    width: canvas,
    height: canvas,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let cream = color(0xF6EEDF)
let fur = color(0xF7ECD9)
let outline = color(0x6E5C49)
let innerEar = color(0xF0B98A)
let blush = color(0xF2B48C)
let stripe = color(0xC49A67)
let eye = color(0x3B342E)

ctx.setLineJoin(.round)
ctx.setLineCap(.round)

// Background rounded square
ctx.addPath(CGPath(roundedRect: CGRect(x: 40, y: 40, width: 944, height: 944), cornerWidth: 210, cornerHeight: 210, transform: nil))
ctx.setFillColor(cream)
ctx.fillPath()

// Tail (behind body)
ctx.setStrokeColor(outline)
ctx.setLineWidth(58)
ctx.beginPath()
ctx.move(to: CGPoint(x: 700, y: 240))
ctx.addCurve(to: CGPoint(x: 838, y: 110), control1: CGPoint(x: 810, y: 280), control2: CGPoint(x: 862, y: 178))
ctx.strokePath()
ctx.setStrokeColor(fur)
ctx.setLineWidth(44)
ctx.beginPath()
ctx.move(to: CGPoint(x: 700, y: 240))
ctx.addCurve(to: CGPoint(x: 838, y: 110), control1: CGPoint(x: 810, y: 280), control2: CGPoint(x: 862, y: 178))
ctx.strokePath()

// Body
ctx.setFillColor(color(0xF1E3CB))
ctx.fillEllipse(in: CGRect(x: 282, y: 70, width: 460, height: 400))
ctx.setStrokeColor(outline)
ctx.setLineWidth(24)
ctx.strokeEllipse(in: CGRect(x: 282, y: 70, width: 460, height: 400))

// Paws
for x in [352, 552] {
    let rect = CGRect(x: CGFloat(x), y: 60, width: 120, height: 84)
    ctx.setFillColor(fur)
    ctx.fillEllipse(in: rect)
    ctx.setStrokeColor(outline)
    ctx.setLineWidth(20)
    ctx.strokeEllipse(in: rect)
}

// Ears (behind head)
ctx.setFillColor(fur)
ctx.setStrokeColor(outline)
ctx.setLineWidth(22)
for mirror in [false, true] {
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: mirror ? 1024 - x : x, y: y)
    }
    ctx.beginPath()
    ctx.move(to: pt(330, 640))
    ctx.addLine(to: pt(360, 900))
    ctx.addLine(to: pt(500, 730))
    ctx.closePath()
    ctx.fillPath()
    ctx.strokePath()
}

// Head
let headRect = CGRect(x: 272, y: 300, width: 480, height: 480)
ctx.setFillColor(fur)
ctx.fillEllipse(in: headRect)
ctx.setStrokeColor(outline)
ctx.setLineWidth(24)
ctx.strokeEllipse(in: headRect)

// Inner ears
ctx.setFillColor(innerEar)
for mirror in [false, true] {
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: mirror ? 1024 - x : x, y: y)
    }
    ctx.beginPath()
    ctx.move(to: pt(352, 655))
    ctx.addLine(to: pt(372, 830))
    ctx.addLine(to: pt(470, 715))
    ctx.closePath()
    ctx.fillPath()
}

// Forehead stripes
ctx.setStrokeColor(stripe)
ctx.setLineWidth(28)
for (x, y1, y2) in [(560, 700, 790), (614, 688, 768), (662, 664, 736)] {
    ctx.beginPath()
    ctx.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y1)))
    ctx.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y2)))
    ctx.strokePath()
}

// Happy closed eyes (∩)
ctx.setStrokeColor(eye)
ctx.setLineWidth(30)
for x in [420, 604] {
    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: CGFloat(x), y: 556), radius: 54, startAngle: 0, endAngle: .pi, clockwise: false)
    ctx.strokePath()
}

// Blush
ctx.setFillColor(blush)
for x in [348, 676] {
    ctx.fillEllipse(in: CGRect(x: CGFloat(x) - 40, y: 430, width: 80, height: 80))
}

// ω mouth
ctx.setLineWidth(20)
for x in [492, 532] {
    ctx.beginPath()
    ctx.addArc(center: CGPoint(x: CGFloat(x), y: 505), radius: 24, startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
}

// Whiskers
ctx.setStrokeColor(color(0x6E5C49, 0.5))
ctx.setLineWidth(14)
for mirror in [false, true] {
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: mirror ? 1024 - x : x, y: y)
    }
    ctx.beginPath()
    ctx.move(to: pt(330, 590))
    ctx.addLine(to: pt(228, 616))
    ctx.strokePath()
    ctx.beginPath()
    ctx.move(to: pt(330, 545))
    ctx.addLine(to: pt(224, 534))
    ctx.strokePath()
}

let image = ctx.makeImage()!
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : URL(fileURLWithPath: "icon_1024.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
print("Wrote \(output.path)")
