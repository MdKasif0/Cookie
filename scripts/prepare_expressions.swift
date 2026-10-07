// Prepares the expression sticker set: trims transparent margins from
// each supplied pose and writes it as an asset-catalog imageset.
// Usage: swift scripts/prepare_expressions.swift <folder-with-pngs>

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

setvbuf(stdout, nil, _IONBF, 0)
guard CommandLine.arguments.count > 1 else {
    print("usage: prepare_expressions.swift <folder>"); exit(1)
}
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let projectRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let catalog = projectRoot.appendingPathComponent("Cookie/Assets/Assets.xcassets", isDirectory: true)

let expressions: [(file: String, name: String)] = [
    ("cookie-angry.png", "cookie-angry"),
    ("cookie-cool.png", "cookie-cool"),
    ("cookie-dizzy.png", "cookie-dizzy"),
    ("cookie-embarrassed.png", "cookie-embarrassed"),
    ("cookie-eyes-close.png", "cookie-eyes-close"),
    ("cookie-hungry.png", "cookie-hungry"),
    ("cookie-mischievous.png", "cookie-mischievous"),
    ("cookie-scared.png", "cookie-scared"),
    ("cookie-shy.png", "cookie-shy"),
    ("cookie-sleep.png", "cookie-sleep"),
    ("cookie-walk.png", "cookie-walk")
]

func trim(_ image: CGImage) -> CGImage? {
    let width = image.width, height = image.height
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let data = context.data else { return nil }
    let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
    var minX = width, maxX = 0, minY = height, maxY = 0
    var any = false
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 24 {
            any = true
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard any else { return nil }
    return image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

for (file, name) in expressions {
    let url = folder.appendingPathComponent(file)
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let base = CGImageSourceCreateImageAtIndex(source, 0, nil),
          let trimmed = trim(base) else {
        print("SKIP \(file) (missing or empty)")
        continue
    }
    let imagesetDir = catalog.appendingPathComponent("\(name).imageset", isDirectory: true)
    try? FileManager.default.createDirectory(at: imagesetDir, withIntermediateDirectories: true)
    writePNG(trimmed, to: imagesetDir.appendingPathComponent("\(name).png"))
    let contents = """
    {
      "images" : [
        {
          "filename" : "\(name).png",
          "idiom" : "universal"
        }
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """
    try? contents.write(to: imagesetDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
    print("wrote \(name): \(trimmed.width)x\(trimmed.height)")
}
