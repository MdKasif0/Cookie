// Analyzes the Cookie reference image: alpha coverage, background
// transparency, and normalized positions of dark features (eyes, mouth)
// and pink blush regions. Usage: swift scripts/analyze_reference.swift <png>

import Foundation
import CoreGraphics
import ImageIO

setvbuf(stdout, nil, _IONBF, 0)

let url = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "cookie.png")
guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("could not load image"); exit(1)
}
let width = image.width, height = image.height
print("size: \(width)x\(height)")

let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
let bufferBytes = width * height * 4
let buffer = UnsafeMutableRawPointer.allocate(byteCount: bufferBytes, alignment: 64)
defer { buffer.deallocate() }
let pixels = buffer.bindMemory(to: UInt8.self, capacity: bufferBytes)
let ctx = CGContext(data: buffer, width: width, height: height, bitsPerComponent: 8,
                    bytesPerRow: width * 4, space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

// Corner alpha check (is background transparent or black?)
func alphaAt(_ x: Int, _ y: Int) -> UInt8 { pixels[(y * width + x) * 4 + 3] }
print("corner alpha (0,0)=\(alphaAt(0,0)) (w-1,h-1)=\(alphaAt(width-1, height-1)) mid-left=\(alphaAt(0, height/2))")

// Alpha bounding box (trim margins)
var minX = width, maxX = 0, minY = height, maxY = 0
var opaqueCount = 0
for y in 0..<height {
    for x in 0..<width {
        if alphaAt(x, y) > 24 {
            opaqueCount += 1
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
print("alpha bbox: x \(minX)...\(maxX), y \(minY)...\(maxY) (top-left origin), opaque px: \(opaqueCount)")

// Dark features: eyes + mouth are the only near-black regions.
// Bin dark pixels into clusters via a coarse grid, then report boxes.
var darkGrid = [Bool](repeating: false, count: width * height)
for y in 0..<height {
    for x in 0..<width {
        let i = (y * width + x) * 4
        let (r, g, b, a) = (pixels[i], pixels[i+1], pixels[i+2], pixels[i+3])
        if a > 200 && r < 90 && g < 90 && b < 90 {
            darkGrid[y * width + x] = true
        }
    }
}
// flood fill clusters
var visited = [Bool](repeating: false, count: width * height)
var clusters: [(minX: Int, minY: Int, maxX: Int, maxY: Int, count: Int)] = []
for y in stride(from: 0, to: height, by: 2) {
    for x in stride(from: 0, to: width, by: 2) where darkGrid[y * width + x] && !visited[y * width + x] {
        var stack = [(x, y)], box = (minX: x, minY: y, maxX: x, maxY: y, count: 0)
        while let (cx, cy) = stack.popLast() {
            guard cx >= 0, cx < width, cy >= 0, cy < height,
                  darkGrid[cy * width + cx], !visited[cy * width + cx] else { continue }
            visited[cy * width + cx] = true
            box.count += 1
            box.minX = min(box.minX, cx); box.maxX = max(box.maxX, cx)
            box.minY = min(box.minY, cy); box.maxY = max(box.maxY, cy)
            for (dx, dy) in [(2,0),(-2,0),(0,2),(0,-2)] { stack.append((cx+dx, cy+dy)) }
        }
        if box.count > 400 { clusters.append(box) }
    }
}
clusters.sort { $0.minX < $1.minX }
print("dark clusters (normalized to alpha bbox):")
for c in clusters {
    let nx = Double(c.minX - minX) / Double(maxX - minX)
    let nx2 = Double(c.maxX - minX) / Double(maxX - minX)
    let ny = Double(c.minY - minY) / Double(maxY - minY)
    let ny2 = Double(c.maxY - minY) / Double(maxY - minY)
    print(String(format: "  x %.3f–%.3f, yTop %.3f–%.3f, center (%.3f, %.3f), px %d",
                 nx, nx2, ny, ny2,
                 Double(c.minX + c.maxX) / 2 / Double(maxX - minX),
                 Double(c.minY + c.maxY) / 2 / Double(maxY - minY),
                 c.count))
}

// Pink blush: r noticeably above g/b, soft pink range — fast grid density scan
let gridSize = 24
var cellCounts = [Int](repeating: 0, count: gridSize * gridSize)
func isPink(_ i: Int) -> Bool {
    let (r, g, b, a) = (pixels[i], pixels[i+1], pixels[i+2], pixels[i+3])
    return a > 200 && r > 215 && r - b > 25 && r - g > 20 && g > 130
}
for y in 0..<height {
    for x in 0..<width {
        if isPink((y * width + x) * 4) {
            cellCounts[(y * gridSize / height) * gridSize + (x * gridSize / width)] += 1
        }
    }
}
let cellArea = (width / gridSize) * (height / gridSize)
print("pink density grid (rows top→bottom, showing cells >20% pink):")
for row in 0..<gridSize {
    var line = ""
    for col in 0..<gridSize {
        let density = Double(cellCounts[row * gridSize + col]) / Double(cellArea)
        line += density > 0.2 ? "#" : (density > 0.05 ? "+" : ".")
    }
    print("  \(line)")
}

// Sample fur color from a patch above the eyes (forehead center)
let fx = (minX + maxX) / 2, fy = minY + (maxY - minY) / 5
let fi = (fy * width + fx) * 4
print(String(format: "fur sample @(%d,%d): r=%d g=%d b=%d", fx, fy, pixels[fi], pixels[fi+1], pixels[fi+2]))
