import AppKit
import SpriteKit
import os

/// Loads, trims, and caches the expression stickers as canvas-sized
/// textures. Every sticker is normalized so the cat herself renders at
/// the same size as the base pose: detached decorations (hearts, sparks,
/// sweat drops) are ignored by taking the largest connected opaque
/// component, that component's longest side is matched to the base
/// artwork's, and its feet sit on the same ground line.
@MainActor
final class ExpressionArtSource {
    static let shared = ExpressionArtSource()

    private let log = Logger(subsystem: "com.cookie.mac", category: "Sprites")
    private var cache: [String: SKTexture] = [:]

    func texture(for art: CookieExpressionArt, config: CookieAppearanceConfig) -> SKTexture? {
        let key = "\(config.renderKey)|\(art.rawValue)"
        if let cached = cache[key] {
            return cached
        }
        guard let baked = bake(art, config: config) else { return nil }
        cache[key] = baked
        return baked
    }

    private func bake(_ art: CookieExpressionArt, config: CookieAppearanceConfig) -> SKTexture? {
        guard let image = NSImage(named: NSImage.Name(art.assetName)) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return nil
        }
        let canvas = CookieSpriteRenderer.canvasSize
        let scale: CGFloat = 2

        // Normalize: match the cat (largest component) to the base pose's
        // size, feet on the ground line, horizontally centered on the body.
        let cat = Self.catComponentBounds(in: cgImage)
        let drawRect: CGRect
        if let cat {
            let drawSize = Self.drawSize(forSticker: cgImage, catBounds: cat, canvas: canvas)
            drawRect = Self.alignedRect(
                forSticker: cgImage, catBounds: cat, drawSize: drawSize, canvas: canvas
            )
            log.debug("\(art.rawValue, privacy: .public) normalized (cat \(Int(cat.width))×\(Int(cat.height)) px of \(cgImage.width)×\(cgImage.height))")
        } else {
            // No readable component — fall back to a plain fit.
            drawRect = ReferenceImageSource.fitRect(
                aspect: Double(cgImage.width) / Double(cgImage.height), canvas: canvas
            )
        }

        let context = CGContext(
            data: nil,
            width: Int(canvas.width * scale), height: Int(canvas.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)
        context.interpolationQuality = .high

        // Draw the sticker, take a full-canvas snapshot for the alpha
        // pass, then apply the chosen fur color as a multiply tint kept
        // inside the cat by a destination-in pass with that snapshot.
        context.draw(cgImage, in: drawRect)
        guard let stickerImage = context.makeImage() else { return nil }

        context.clear(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
        if let multiply = config.furColor.multiplyColor {
            context.draw(stickerImage, in: CGRect(origin: .zero, size: canvas))
            context.setBlendMode(.multiply)
            context.setFillColor(multiply)
            context.fill(CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height))
            context.setBlendMode(.destinationIn)
            context.draw(stickerImage, in: CGRect(origin: .zero, size: canvas))
            context.setBlendMode(.normal)
        } else {
            context.draw(stickerImage, in: CGRect(origin: .zero, size: canvas))
        }
        softenClippedEdges(of: drawRect, canvas: canvas, in: context)
        return context.makeImage().map { SKTexture(cgImage: $0) }
    }

    private func softenClippedEdges(of drawRect: CGRect, canvas: CGSize, in context: CGContext) {
        let fade = canvas.width * 0.10
        context.setBlendMode(.destinationOut)
        func fadeEdge(from: CGPoint, to: CGPoint) {
            let gradient = CGGradient(
                colorsSpace: nil,
                colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray,
                locations: [0, 1]
            )!
            context.drawLinearGradient(
                gradient, start: from, end: to,
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
        }
        if drawRect.maxY > canvas.height {
            fadeEdge(from: CGPoint(x: 0, y: canvas.height), to: CGPoint(x: 0, y: canvas.height - fade))
        }
        if drawRect.minY < 0 {
            fadeEdge(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: fade))
        }
        if drawRect.maxX > canvas.width {
            fadeEdge(from: CGPoint(x: canvas.width, y: 0), to: CGPoint(x: canvas.width - fade, y: 0))
        }
        if drawRect.minX < 0 {
            fadeEdge(from: CGPoint(x: 0, y: 0), to: CGPoint(x: fade, y: 0))
        }
        context.setBlendMode(.normal)
    }

    // MARK: - Size normalization

    /// Finds the largest connected opaque component (the cat) in a
    /// downsampled alpha grid. Returns its bounds in pixels of the
    /// original image.
    static func catComponentBounds(in image: CGImage) -> CGRect? {
        let gridWidth = 128
        let gridHeight = max(8, Int(Double(gridWidth) * Double(image.height) / Double(image.width)))
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let context = CGContext(
            data: nil, width: gridWidth, height: gridHeight, bitsPerComponent: 8,
            bytesPerRow: gridWidth * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: gridWidth, height: gridHeight))
        guard let data = context.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: gridWidth * gridHeight * 4)

        var opaque = [Bool](repeating: false, count: gridWidth * gridHeight)
        for index in 0..<(gridWidth * gridHeight) where pixels[index * 4 + 3] > 24 {
            opaque[index] = true
        }

        // Iterative flood fill over the largest component.
        var visited = [Bool](repeating: false, count: gridWidth * gridHeight)
        var best = (minX: 0, minY: 0, maxX: 0, maxY: 0, area: 0)
        for startY in 0..<gridHeight {
            for startX in 0..<gridWidth {
                let startIndex = startY * gridWidth + startX
                guard opaque[startIndex], !visited[startIndex] else { continue }
                var stack = [(startX, startY)]
                visited[startIndex] = true
                var minX = startX, maxX = startX, minY = startY, maxY = startY, area = 0
                while let (x, y) = stack.popLast() {
                    area += 1
                    minX = min(minX, x); maxX = max(maxX, x)
                    minY = min(minY, y); maxY = max(maxY, y)
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, nx < gridWidth, ny >= 0, ny < gridHeight else { continue }
                        let neighbor = ny * gridWidth + nx
                        if opaque[neighbor], !visited[neighbor] {
                            visited[neighbor] = true
                            stack.append((nx, ny))
                        }
                    }
                }
                if area > best.area {
                    best = (minX, minY, maxX, maxY, area)
                }
            }
        }
        guard best.area > 16 else { return nil }

        // Grid cells → original-image pixel bounds.
        let scaleX = Double(image.width) / Double(gridWidth)
        let scaleY = Double(image.height) / Double(gridHeight)
        return CGRect(
            x: CGFloat(Double(best.minX) * scaleX),
            y: CGFloat(Double(best.minY) * scaleY),
            width: CGFloat(Double(best.maxX - best.minX + 1) * scaleX),
            height: CGFloat(Double(best.maxY - best.minY + 1) * scaleY)
        )
    }

    /// Draw size for a sticker so its cat matches the base artwork: the
    /// base cat fills the art rect's height, so the sticker's cat's
    /// longest side is matched to it. Clamped so wide poses (lying down)
    /// and decoration-heavy poses stay mostly inside the canvas.
    static func drawSize(forSticker image: CGImage, catBounds: CGRect, canvas: CGSize) -> CGSize {
        let art = ReferenceImageSource.artRect(canvas: CGSize(width: 180, height: 180))
        let catLongest = max(catBounds.width, catBounds.height)
        guard catLongest > 0 else {
            return ReferenceImageSource.fitRect(
                aspect: Double(image.width) / Double(image.height), canvas: canvas
            ).size
        }
        let artRect = ReferenceImageSource.artRect(canvas: CGSize(width: 180, height: 180))
        let reference = max(artRect.width, artRect.height) // the base cat's longest side
        let scale = reference / catLongest
        var width = CGFloat(image.width) * scale
        var height = CGFloat(image.height) * scale

        // Keep wide (lying) poses and tall poses mostly inside the canvas.
        let maxWidth = canvas.width * 1.08
        let maxHeight = canvas.height * 1.35
        if width > maxWidth {
            height *= maxWidth / width
            width = maxWidth
        }
        if height > maxHeight {
            width *= maxHeight / height
            height = maxHeight
        }
        _ = art
        return CGSize(width: width, height: height)
    }

    /// Positions a sticker so the cat's feet sit on the base ground line
    /// and the body is horizontally centered where the base cat stands.
    static func alignedRect(forSticker image: CGImage, catBounds: CGRect,
                            drawSize: CGSize, canvas: CGSize) -> CGRect {
        let artRect = ReferenceImageSource.artRect(canvas: CGSize(width: 180, height: 180))
        // Cat fractions within the sticker image (top-left origin):
        let catFractionCenterX = catBounds.midX / CGFloat(image.width)
        let catFractionBottom = catBounds.maxY / CGFloat(image.height)
        // Bottom-left CG coordinates: the cat's bottom lands on the base
        // ground line, its center on the base cat's horizontal center.
        let minX = artRect.midX - catFractionCenterX * drawSize.width
        let minY = artRect.minY - (1 - catFractionBottom) * drawSize.height
        return CGRect(x: minX, y: minY, width: drawSize.width, height: drawSize.height)
    }

    #if DEBUG
    /// Debug: writes every baked sticker for visual review.
    static func exportAll(to directory: URL, config: CookieAppearanceConfig = CookieAppearanceConfig()) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for art in CookieExpressionArt.allCases {
            guard let texture = shared.texture(for: art, config: config) else { continue }
            let cgImage = texture.cgImage()
            let destination = CGImageDestinationCreateWithURL(
                directory.appendingPathComponent("\(art.rawValue).png") as CFURL,
                "public.png" as CFString, 1, nil
            )
            if let destination {
                CGImageDestinationAddImage(destination, cgImage, nil)
                CGImageDestinationFinalize(destination)
            }
        }
    }
    #endif
}
