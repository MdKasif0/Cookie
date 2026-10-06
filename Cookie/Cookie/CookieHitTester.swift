import Foundation
import CoreGraphics
import ImageIO

/// Tests whether a point in the companion canvas lands on Cookie's
/// artwork. The companion SKView uses this so clicks on transparent
/// pixels pass through to whatever is beneath — Cookie only ever
/// intercepts interaction on her actual silhouette.
@MainActor
final class CookieHitTester {
    private let artRect: CGRect
    /// Downsampled artwork alpha, dilated so the cat is easy to grab.
    private var opaqueCells: [Bool] = []
    private let gridWidth = 96
    private let gridHeight = 101

    init?(canvasSize: CGSize) {
        guard let image = ReferenceImageSource.loadArtwork() else { return nil }
        artRect = ReferenceImageSource.artRect(canvas: canvasSize)

        let width = gridWidth, height = gridHeight
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)

        var raw = [Bool](repeating: false, count: width * height)
        for index in 0..<(width * height) where pixels[index * 4 + 3] > 12 {
            raw[index] = true
        }

        // Dilate by two cells: a small grab margin around the silhouette.
        var dilated = raw
        let reach = 2
        for y in 0..<height {
            for x in 0..<width where !raw[y * width + x] {
                var hit = false
                let minY = max(0, y - reach), maxY = min(height - 1, y + reach)
                let minX = max(0, x - reach), maxX = min(width - 1, x + reach)
                for cy in minY...maxY where !hit {
                    for cx in minX...maxX where raw[cy * width + cx] {
                        hit = true
                        break
                    }
                }
                dilated[y * width + x] = hit
            }
        }
        opaqueCells = dilated
    }

    /// True when the canvas point (bottom-left origin, points) is on the
    /// cat — or close enough to grab her comfortably.
    func isOpaque(canvasPoint: CGPoint) -> Bool {
        let nx = (canvasPoint.x - artRect.minX) / artRect.width
        let ny = 1 - (canvasPoint.y - artRect.minY) / artRect.height
        guard nx >= 0, nx < 1, ny >= 0, ny < 1 else { return false }
        let cellX = min(gridWidth - 1, max(0, Int(nx * CGFloat(gridWidth))))
        let cellY = min(gridHeight - 1, max(0, Int(ny * CGFloat(gridHeight))))
        return opaqueCells[cellY * gridWidth + cellX]
    }

    /// Writes the tested silhouette as a PNG for visual verification.
    func exportMask(to url: URL, cellSize: Int = 6) {
        let width = gridWidth * cellSize, height = gridHeight * cellSize
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(srgbRed: 1, green: 0.97, blue: 0.94, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.18, blue: 0.16, alpha: 0.85))
        for y in 0..<gridHeight {
            for x in 0..<gridWidth where opaqueCells[y * gridWidth + x] {
                context.fill(CGRect(
                    x: CGFloat(x * cellSize),
                    y: CGFloat((gridHeight - 1 - y) * cellSize),
                    width: CGFloat(cellSize),
                    height: CGFloat(cellSize)
                ))
            }
        }
        guard let image = context.makeImage() else { return }
        let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        )
        if let destination {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }
}
