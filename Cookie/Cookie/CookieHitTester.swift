import Foundation
import CoreGraphics
import ImageIO

/// Tests whether a point in the companion canvas lands on Cookie's
/// artwork — and which part of her it touches. The companion SKView uses
/// this so clicks on transparent pixels pass through to whatever is
/// beneath, and so interactions know nose from tail.
@MainActor
final class CookieHitTester {
    private let artRect: CGRect
    /// Downsampled artwork alpha, dilated so the cat is easy to grab.
    private var opaqueCells: [Bool] = []
    private let gridWidth = 96
    private let gridHeight = 101

    /// Interaction zones, normalized to the artwork (top-left origin).
    /// Checked in order — the nose is inside the head, so it wins first.
    /// Measured for the sitting pose (tail curls on the right).
    private static let zones: [(zone: CookieZone, x: Double, y: Double, rx: Double, ry: Double)] = [
        (.nose, 0.450, 0.450, 0.100, 0.080),
        (.head, 0.460, 0.240, 0.400, 0.260),
        (.tail, 0.870, 0.760, 0.130, 0.160),
        (.feet, 0.420, 0.910, 0.340, 0.100),
        (.body, 0.500, 0.620, 0.450, 0.280)
    ]

    init?(canvasSize: CGSize) {
        guard let image = ReferenceImageSource.loadArtwork() else { return nil }
        artRect = ReferenceImageSource.artRect(canvas: canvasSize)

        let width = gridWidth, height = gridHeight
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
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
        guard let normalized = normalizedPoint(from: canvasPoint) else { return false }
        let cellX = min(gridWidth - 1, max(0, Int(normalized.x * CGFloat(gridWidth))))
        let cellY = min(gridHeight - 1, max(0, Int(normalized.y * CGFloat(gridHeight))))
        return opaqueCells[cellY * gridWidth + cellX]
    }

    /// The body part under the canvas point, or nil when off the cat.
    func zone(at canvasPoint: CGPoint) -> CookieZone? {
        guard isOpaque(canvasPoint: canvasPoint),
              let normalized = normalizedPoint(from: canvasPoint) else { return nil }
        for zone in Self.zones {
            let dx = (normalized.x - zone.x) / zone.rx
            let dy = (normalized.y - zone.y) / zone.ry
            if dx * dx + dy * dy <= 1 {
                return zone.zone
            }
        }
        // On the silhouette but outside every zone: treat as body.
        return .body
    }

    private func normalizedPoint(from canvasPoint: CGPoint) -> CGPoint? {
        let nx = (canvasPoint.x - artRect.minX) / artRect.width
        let ny = 1 - (canvasPoint.y - artRect.minY) / artRect.height
        guard nx >= 0, nx < 1, ny >= 0, ny < 1 else { return nil }
        return CGPoint(x: nx, y: ny)
    }

    /// Writes the tested silhouette — with interaction zone outlines —
    /// as a PNG for visual verification.
    func exportMask(to url: URL, cellSize: Int = 6) {
        let width = gridWidth * cellSize, height = gridHeight * cellSize
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return }
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

        // Zone outlines (top-left normalized → canvas bottom-left coords).
        let art = ReferenceImageSource.artRect(canvas: CGSize(width: 180, height: 180))
        let scaleX = CGFloat(width) / art.width
        let scaleY = CGFloat(height) / art.height
        let styles: [(CGColor, CGFloat)] = [
            (CGColor(srgbRed: 0.75, green: 0.30, blue: 0.25, alpha: 0.9), 2),   // nose
            (CGColor(srgbRed: 0.85, green: 0.55, blue: 0.20, alpha: 0.9), 2),   // head
            (CGColor(srgbRed: 0.35, green: 0.55, blue: 0.30, alpha: 0.9), 2),   // tail
            (CGColor(srgbRed: 0.30, green: 0.45, blue: 0.65, alpha: 0.9), 2),   // feet
            (CGColor(srgbRed: 0.45, green: 0.40, blue: 0.55, alpha: 0.9), 2)    // body
        ]
        for (index, zone) in Self.zones.enumerated() {
            let style = styles[index]
            context.setStrokeColor(style.0)
            context.setLineWidth(style.1)
            let center = CGPoint(
                x: art.minX + CGFloat(zone.x) * art.width,
                y: art.maxY - CGFloat(zone.y) * art.height
            )
            // Map through the art rect into mask pixels.
            let px = (center.x - art.minX) * scaleX
            let py = (center.y - art.minY) * scaleY
            let rx = CGFloat(zone.rx) * art.width * scaleX
            let ry = CGFloat(zone.ry) * art.height * scaleY
            context.strokeEllipse(in: CGRect(x: px - rx, y: py - ry, width: rx * 2, height: ry * 2))
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
