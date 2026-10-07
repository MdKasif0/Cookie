// Prepares the shipped Cookie artwork from the user's reference image:
//  1. trims transparent margins → CookieArt imageset (the live sprite)
//  2. composites the cat onto a cream rounded square → AppIcon set
// Usage: swift scripts/prepare_reference.swift <reference.png>
// Feature coordinates used by ReferenceImageSource were measured from
// this same image with scripts/analyze_reference.swift.

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

setvbuf(stdout, nil, _IONBF, 0)
guard CommandLine.arguments.count > 1 else {
    print("usage: prepare_reference.swift <reference.png>"); exit(1)
}
let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil)!
guard let base = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("could not read image"); exit(1)
}

// Computes the alpha bounding box so the script works with any pose of
// the artwork.
var minX = base.width, maxX = 0, minY = base.height, maxY = 0
do {
    let width = base.width, height = base.height
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { print("crop failed"); exit(1) }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 24 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
let crop = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let trimmed = base.cropping(to: crop) else {
    print("crop failed"); exit(1)
}
print("trimmed: \(trimmed.width)x\(trimmed.height) from \(crop)")

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// 1. CookieArt imageset
let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()      // scripts/
    .deletingLastPathComponent()      // project root
let imagesetDir = projectRoot
    .appendingPathComponent("Cookie/Assets/Assets.xcassets/CookieArt.imageset", isDirectory: true)
try? FileManager.default.createDirectory(at: imagesetDir, withIntermediateDirectories: true)
writePNG(trimmed, to: imagesetDir.appendingPathComponent("cookie.png"))
let imagesetJSON = """
{
  "images" : [
    {
      "filename" : "cookie.png",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try? imagesetJSON.write(to: imagesetDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("wrote CookieArt.imageset")

// 2. App icon: cream rounded square + the cat
let canvas = 1024
let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                    bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
ctx.setFillColor(color(0xF6EEDF))
let bg = CGRect(x: 40, y: 40, width: 944, height: 944)
let rounded = CGPath(roundedRect: bg, cornerWidth: 210, cornerHeight: 210, transform: nil)
ctx.addPath(rounded)
ctx.fillPath()

// Cat occupies ~76% of the width, settled toward the bottom edge.
let catWidth = 780.0
let catHeight = catWidth * Double(trimmed.height) / Double(trimmed.width)
let catRect = CGRect(x: (Double(canvas) - catWidth) / 2, y: 64,
                     width: catWidth, height: catHeight)
ctx.draw(trimmed, in: catRect)

let icon = ctx.makeImage()!
let iconSetDir = projectRoot
    .appendingPathComponent("Cookie/Assets/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
writePNG(icon, to: iconSetDir.appendingPathComponent("icon_512x512@2x.png"))
print("wrote icon master")
