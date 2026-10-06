import AppKit
import SpriteKit
import os

/// Animates Cookie from the shipped reference artwork (the user's final
/// image). The base pose is the artwork itself; every animation is derived
/// from it with bottom-anchored transforms plus soft, sampled overlays
/// (closed eyes, open mouth, boosted blush), so Cookie always looks
/// exactly like the reference. Bundle sprite sheets still outrank this
/// source once real frame art exists, and the vector placeholder remains
/// the last resort if the artwork asset is missing.
@MainActor
final class ReferenceImageSource: AnimationFrameSource {
    static let artName = "CookieArt"
    /// Frame bitmaps are baked at this multiple of the point canvas.
    private static let bakeScale: CGFloat = 2

    // MARK: - Measured features (normalized to the artwork, top-left origin)

    private struct Feature {
        let x: Double, y: Double, rx: Double, ry: Double
        func point(in rect: CGRect) -> CGPoint {
            CGPoint(x: rect.minX + CGFloat(x) * rect.width,
                    y: rect.minY + (1 - CGFloat(y)) * rect.height)
        }
        func scaledSize(in rect: CGRect, factor: CGFloat = 1) -> CGSize {
            CGSize(width: CGFloat(rx) * factor * rect.width * 2,
                   height: CGFloat(ry) * factor * rect.height * 2)
        }
    }

    private static let eyeLeft = Feature(x: 0.309, y: 0.362, rx: 0.036, ry: 0.041)
    private static let eyeRight = Feature(x: 0.596, y: 0.428, rx: 0.041, ry: 0.042)
    private static let mouth = Feature(x: 0.431, y: 0.435, rx: 0.045, ry: 0.022)
    private static let blushLeft = Feature(x: 0.230, y: 0.432, rx: 0.075, ry: 0.075)
    private static let blushRight = Feature(x: 0.623, y: 0.500, rx: 0.070, ry: 0.070)

    private enum Overlay {
        case eyesClosed
        case eyesHalf
        case eyesHappy
        case eyesWide
        case mouthOpen
        case mouthOpenWide
        case mouthFlat
        case blushBoost
    }

    private struct Frame {
        var scaleX: CGFloat = 1
        var scaleY: CGFloat = 1
        var rotation: CGFloat = 0      // degrees, applied around the feet
        var offsetX: CGFloat = 0
        var offsetY: CGFloat = 0       // points, up is positive
        var overlays: [Overlay] = []
    }

    // MARK: - Frame plans

    private static func plan(for animation: CookieAnimationId) -> [Frame]? {
        switch animation {
        case .idle:
            return [Frame(), Frame(scaleX: 0.99, scaleY: 1.015), Frame(), Frame(scaleX: 1.005, scaleY: 0.99)]
        case .idleBlink:
            return [Frame(), Frame(overlays: [.eyesClosed]), Frame(overlays: [.eyesClosed]), Frame()]
        case .sit:
            return [Frame(scaleY: 0.98, offsetY: 2), Frame(scaleY: 0.985, offsetY: 1.5)]
        case .sleep:
            return [
                Frame(scaleY: 0.97, rotation: 2, overlays: [.eyesClosed]),
                Frame(scaleY: 0.955, rotation: 2, overlays: [.eyesClosed])
            ]
        case .wake:
            return [
                Frame(overlays: [.eyesClosed]),
                Frame(offsetY: -1, overlays: [.eyesHalf]),
                Frame(scaleY: 1.01)
            ]
        case .stretch:
            return [
                Frame(scaleY: 0.94, offsetY: 4),
                Frame(scaleY: 1.04, offsetY: -4),
                Frame()
            ]
        case .yawn:
            return [
                Frame(overlays: [.mouthOpen]),
                Frame(scaleY: 1.02, overlays: [.mouthOpenWide, .eyesClosed]),
                Frame(overlays: [.mouthOpen]),
                Frame()
            ]
        case .groom:
            return [
                Frame(rotation: 4, offsetY: 3, overlays: [.eyesClosed]),
                Frame(rotation: 5, offsetY: 4, overlays: [.eyesClosed]),
                Frame(rotation: 4, offsetY: 3, overlays: [.eyesClosed])
            ]
        case .walkLeft, .walkRight:
            return [
                Frame(offsetX: -3, offsetY: -1), Frame(offsetY: 1),
                Frame(offsetX: 3, offsetY: -1), Frame(offsetY: 1)
            ]
        case .runLeft, .runRight:
            return [
                Frame(rotation: -2, offsetX: -5, offsetY: -2), Frame(offsetY: 2),
                Frame(rotation: 2, offsetX: 5, offsetY: -2), Frame(offsetY: 2)
            ]
        case .curious:
            return [Frame(rotation: 3), Frame(rotation: -2)]
        case .happy:
            return [
                Frame(scaleY: 0.93, offsetY: 3, overlays: [.blushBoost, .eyesHappy]),
                Frame(scaleY: 1.06, offsetY: -5, overlays: [.blushBoost, .eyesHappy]),
                Frame(overlays: [.blushBoost, .eyesHappy])
            ]
        case .surprised:
            return [
                Frame(scaleY: 1.03, offsetY: -2, overlays: [.eyesWide, .mouthOpen]),
                Frame(overlays: [.eyesWide, .mouthOpen])
            ]
        case .scared:
            return [
                Frame(scaleY: 0.95, offsetY: 2, overlays: [.eyesWide]),
                Frame(scaleY: 0.93, offsetY: 3, overlays: [.eyesWide])
            ]
        case .annoyed:
            return [Frame(overlays: [.eyesHalf, .mouthFlat]), Frame(overlays: [.eyesHalf, .mouthFlat])]
        case .playful:
            return [
                Frame(scaleY: 0.92, offsetY: 4, overlays: [.eyesWide]),
                Frame(scaleY: 0.96, offsetY: 2, overlays: [.eyesHappy]),
                Frame(scaleY: 0.92, offsetY: 4, overlays: [.eyesWide])
            ]
        case .eat:
            return [
                Frame(offsetY: 2, overlays: [.mouthOpen]),
                Frame(offsetY: 3, overlays: [.mouthOpen]),
                Frame(offsetY: 2, overlays: [.mouthOpen]),
                Frame(offsetY: 3, overlays: [.mouthOpenWide])
            ]
        case .drink:
            return [
                Frame(offsetY: 3, overlays: [.mouthOpen]),
                Frame(offsetY: 4, overlays: [.mouthOpen])
            ]
        case .pet:
            return [
                Frame(scaleY: 0.92, offsetY: 2, overlays: [.blushBoost, .eyesHappy]),
                Frame(scaleY: 1.05, offsetY: -4, overlays: [.blushBoost, .eyesHappy]),
                Frame(overlays: [.blushBoost, .eyesHappy])
            ]
        case .meow:
            return [
                Frame(offsetY: -2, overlays: [.mouthOpen, .eyesHalf]),
                Frame(offsetY: -3, overlays: [.mouthOpenWide, .eyesHalf]),
                Frame(offsetY: -2, overlays: [.mouthOpen])
            ]
        case .jump:
            return [
                Frame(scaleY: 0.9, offsetY: 3),
                Frame(scaleX: 0.97, scaleY: 1.08, offsetY: -10),
                Frame(scaleY: 1.02)
            ]
        case .fall:
            return [Frame(scaleY: 1.04, rotation: -3), Frame(scaleY: 1.04, rotation: 3)]
        case .pickedUp:
            return [Frame(scaleY: 1.03, offsetY: -2), Frame(scaleY: 1.02, offsetY: -1)]
        case .dropped:
            return [
                Frame(scaleY: 0.88, offsetY: 5, overlays: [.eyesClosed]),
                Frame(scaleY: 0.95, offsetY: 2, overlays: [.eyesWide]),
                Frame()
            ]
        }
    }

    // MARK: - Baking

    private let cache = NSCache<NSString, NSArray>()
    private var sampledColors: SampledColors?

    func textures(for animation: CookieAnimationId, palette: CharacterPalette) -> [SKTexture]? {
        guard let base = Self.loadArtwork(), let plan = Self.plan(for: animation) else { return nil }
        let colors = sampleColors(from: base)
        let key = "\(palette.fur.description)|\(animation.rawValue)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached as? [SKTexture]
        }
        let canvas = CookieSpriteRenderer.canvasSize
        let textures = plan.map { frame in
            SKTexture(cgImage: bake(frame: frame, base: base, colors: colors,
                                    canvas: canvas, palette: palette))
        }
        cache.setObject(textures as NSArray, forKey: key)
        return textures
    }

    /// Drops cached textures, e.g. when the palette changes.
    func invalidate() {
        cache.removeAllObjects()
        sampledColors = nil
    }

    static func loadArtwork() -> CGImage? {
        guard let image = NSImage(named: NSImage.Name(Self.artName)) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// The draw rect for the artwork inside the canvas: fitted, anchored
    /// to the bottom so transforms feel grounded.
    static func artRect(canvas: CGSize) -> CGRect {
        let inset = canvas.width * 0.02
        let available = CGSize(width: canvas.width - inset * 2, height: canvas.height - inset * 1.5)
        let aspect = available.width / available.height
        let imageAspect = 1133.0 / 1193.0
        var size = available
        if imageAspect > aspect {
            size.height = available.width / imageAspect
        } else {
            size.width = available.height * imageAspect
        }
        return CGRect(
            x: (canvas.width - size.width) / 2,
            y: inset * 0.4,
            width: size.width,
            height: size.height
        )
    }

    private func bake(frame: Frame, base: CGImage, colors: SampledColors, canvas: CGSize, palette: CharacterPalette) -> CGImage {
        let scale = Self.bakeScale
        let pixels = CGSize(width: canvas.width * scale, height: canvas.height * scale)
        let ctx = CGContext(
            data: nil, width: Int(pixels.width), height: Int(pixels.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.scaleBy(x: scale, y: scale)
        ctx.interpolationQuality = .high

        let rect = Self.artRect(canvas: canvas)
        // Anchor at the feet: bottom center of the artwork.
        let anchor = CGPoint(x: rect.midX, y: rect.minY)
        ctx.translateBy(x: anchor.x, y: anchor.y)
        ctx.rotate(by: frame.rotation * .pi / 180)
        ctx.scaleBy(x: frame.scaleX, y: frame.scaleY)
        ctx.translateBy(x: -anchor.x, y: -anchor.y - frame.offsetY)
        let drawRect = rect.offsetBy(dx: frame.offsetX, dy: frame.offsetY)

        ctx.draw(base, in: drawRect)

        for overlay in frame.overlays {
            drawOverlay(overlay, in: ctx, base: base, rect: drawRect, colors: colors)
        }

        // Very subtle appearance tint, applied only where the cat is.
        if let tint = palette.artTint {
            ctx.setBlendMode(.sourceAtop)
            ctx.setFillColor(tint.cgColor.copy(alpha: 0.12) ?? tint.cgColor)
            ctx.fill(CGRect(origin: .zero, size: canvas))
            ctx.setBlendMode(.normal)
        }

        return ctx.makeImage() ?? base
    }

    // MARK: - Overlays

    private struct SampledColors {
        var eyeDark: CGColor
        var blush: CGColor
    }

    private func sampleColors(from base: CGImage) -> SampledColors {
        if let sampled = sampledColors {
            return sampled
        }
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        let width = 256, height = 256
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = ctx.data else {
            let fallback = SKColor.black.cgColor
            sampledColors = SampledColors(eyeDark: fallback, blush: fallback)
            return sampledColors!
        }
        let px = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        func probe(_ nx: Double, _ ny: Double) -> CGColor {
            // Buffer row 0 is the image's top row, matching top-left
            // normalized feature coordinates — no flip here.
            let x = min(width - 1, Int(nx * Double(width)))
            let y = min(height - 1, Int(ny * Double(height)))
            let i = (y * width + x) * 4
            return CGColor(srgbRed: CGFloat(px[i]) / 255, green: CGFloat(px[i + 1]) / 255,
                           blue: CGFloat(px[i + 2]) / 255, alpha: 1)
        }
        let colors = SampledColors(
            eyeDark: probe(Self.eyeLeft.x, Self.eyeLeft.y),
            blush: probe(Self.blushLeft.x, Self.blushLeft.y)
        )
        if ProcessInfo.processInfo.environment["COOKIE_SAMPLE_DEBUG"] != nil {
            func desc(_ c: CGColor) -> String {
                let ci = c.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil) ?? c
                let comp = ci.components ?? []
                return comp.map { String(format: "%.2f", $0) }.joined(separator: ", ")
            }
            print("eyeDark = \(desc(colors.eyeDark)); blush = \(desc(colors.blush))")
        }
        sampledColors = colors
        return colors
    }

    /// Clones a patch of real fur from the artwork over a feature, with a
    /// feathered rim, so covers inherit the surrounding clay shading
    /// instead of a flat sampled color. Clones come from the clean bridge
    /// between the eyes; overlapping covers still read as fur.
    private func cloneOver(_ ctx: CGContext, base: CGImage, rect: CGRect,
                           over center: CGPoint, patchSize: CGSize,
                           sourceCenterNorm: CGPoint) {
        let imageWidth = CGFloat(base.width), imageHeight = CGFloat(base.height)
        let patchPixelsW = Int(patchSize.width / rect.width * imageWidth)
        let patchPixelsH = Int(patchSize.height / rect.height * imageHeight)
        guard patchPixelsW > 4, patchPixelsH > 4 else { return }
        let sourceRect = CGRect(
            x: sourceCenterNorm.x * imageWidth - CGFloat(patchPixelsW) / 2,
            y: sourceCenterNorm.y * imageHeight - CGFloat(patchPixelsH) / 2,
            width: CGFloat(patchPixelsW), height: CGFloat(patchPixelsH)
        )
        guard let patch = base.cropping(to: sourceRect) else { return }

        // Feather the patch so its edges dissolve into the destination.
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let feather = CGContext(data: nil, width: patchPixelsW, height: patchPixelsH,
                                bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        feather.draw(patch, in: CGRect(x: 0, y: 0, width: patchPixelsW, height: patchPixelsH))
        feather.setBlendMode(.destinationIn)
        let mid = CGPoint(x: CGFloat(patchPixelsW) / 2, y: CGFloat(patchPixelsH) / 2)
        let gradient = CGGradient(colorsSpace: space, colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0)
        ] as CFArray, locations: [0, 0.72, 1])!
        feather.saveGState()
        feather.translateBy(x: mid.x, y: mid.y)
        feather.scaleBy(x: CGFloat(patchPixelsW) / 2, y: CGFloat(patchPixelsH) / 2)
        feather.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                   endCenter: .zero, endRadius: 1, options: [])
        feather.restoreGState()
        guard let feathered = feather.makeImage() else { return }

        ctx.draw(feathered, in: CGRect(
            x: center.x - patchSize.width / 2,
            y: center.y - patchSize.height / 2,
            width: patchSize.width,
            height: patchSize.height
        ))
    }

    /// A shallow arc — reads as a relaxed ︶ or ︵ lid, not a ring.
    private func strokeEyeArc(_ ctx: CGContext, at center: CGPoint, radius: CGFloat,
                              upper: Bool, color: CGColor, width: CGFloat) {
        ctx.setStrokeColor(color)
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        let sweep: CGFloat = .pi * 0.66
        let start = upper ? (.pi / 2 - sweep / 2) : (3 * .pi / 2 - sweep / 2)
        ctx.addArc(center: center, radius: radius,
                   startAngle: start, endAngle: start + sweep,
                   clockwise: false)
        ctx.strokePath()
    }

    private func drawOverlay(_ overlay: Overlay, in ctx: CGContext, base: CGImage, rect: CGRect, colors: SampledColors) {
        switch overlay {
        case .eyesClosed, .eyesHappy, .eyesWide, .eyesHalf:
            for eye in [Self.eyeLeft, Self.eyeRight] {
                let center = eye.point(in: rect)
                let size = eye.scaledSize(in: rect)
                // Clone from fur directly above each eye: adjacent shading
                // makes the cover seamless.
                func source(for patch: CGSize) -> CGPoint {
                    CGPoint(x: eye.x,
                            y: (eye.y - eye.ry) - patch.height / rect.height / 2 - 0.008)
                }
                switch overlay {
                case .eyesClosed:
                    let patch = CGSize(width: size.width * 2.0, height: size.height * 1.35)
                    cloneOver(ctx, base: base, rect: rect, over: center,
                              patchSize: patch, sourceCenterNorm: source(for: patch))
                    strokeEyeArc(ctx, at: CGPoint(x: center.x, y: center.y + size.height * 0.12),
                                 radius: size.width * 0.62, upper: false,
                                 color: colors.eyeDark, width: size.height * 0.22)
                case .eyesHappy:
                    let patch = CGSize(width: size.width * 2.0, height: size.height * 1.35)
                    cloneOver(ctx, base: base, rect: rect, over: center,
                              patchSize: patch, sourceCenterNorm: source(for: patch))
                    strokeEyeArc(ctx, at: CGPoint(x: center.x, y: center.y - size.height * 0.08),
                                 radius: size.width * 0.62, upper: true,
                                 color: colors.eyeDark, width: size.height * 0.22)
                case .eyesWide:
                    let patch = CGSize(width: size.width * 1.6, height: size.height * 1.6)
                    cloneOver(ctx, base: base, rect: rect, over: center,
                              patchSize: patch, sourceCenterNorm: source(for: patch))
                    ctx.setFillColor(colors.eyeDark)
                    ctx.fillEllipse(in: CGRect(
                        x: center.x - size.width * 0.62, y: center.y - size.height * 0.62,
                        width: size.width * 1.24, height: size.height * 1.24
                    ))
                    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
                    ctx.fillEllipse(in: CGRect(
                        x: center.x - size.width * 0.42, y: center.y + size.height * 0.05,
                        width: size.width * 0.42, height: size.height * 0.42
                    ))
                case .eyesHalf:
                    let patch = CGSize(width: size.width * 1.6, height: size.height * 1.0)
                    cloneOver(ctx, base: base, rect: rect,
                              over: CGPoint(x: center.x, y: center.y + size.height * 0.5),
                              patchSize: patch, sourceCenterNorm: source(for: patch))
                    ctx.setStrokeColor(colors.eyeDark)
                    ctx.setLineWidth(size.height * 0.2)
                    ctx.setLineCap(.round)
                    ctx.move(to: CGPoint(x: center.x - size.width * 0.55, y: center.y - size.height * 0.05))
                    ctx.addLine(to: CGPoint(x: center.x + size.width * 0.55, y: center.y - size.height * 0.05))
                    ctx.strokePath()
                default:
                    break
                }
            }
        case .mouthOpen, .mouthOpenWide, .mouthFlat:
            let center = Self.mouth.point(in: rect)
            let size = Self.mouth.scaledSize(in: rect)
            let patch = CGSize(width: size.width * 1.7, height: size.height * 2.0)
            cloneOver(ctx, base: base, rect: rect, over: center,
                      patchSize: patch,
                      // Fur directly above the mouth, same muzzle shading.
                      sourceCenterNorm: CGPoint(x: Self.mouth.x,
                                                y: (Self.mouth.y - Self.mouth.ry) - patch.height / rect.height / 2 - 0.006))
            switch overlay {
            case .mouthOpen:
                ctx.setFillColor(colors.eyeDark)
                ctx.fillEllipse(in: CGRect(
                    x: center.x - size.width * 0.5, y: center.y - size.height * 1.1,
                    width: size.width, height: size.height * 1.6
                ))
            case .mouthOpenWide:
                ctx.setFillColor(colors.eyeDark)
                let openRect = CGRect(
                    x: center.x - size.width * 0.65, y: center.y - size.height * 1.5,
                    width: size.width * 1.3, height: size.height * 2.2
                )
                ctx.fillEllipse(in: openRect)
                ctx.saveGState()
                ctx.addPath(CGPath(ellipseIn: openRect, transform: nil))
                ctx.clip()
                ctx.setFillColor(colors.blush)
                ctx.fill(CGRect(x: openRect.minX, y: openRect.minY,
                                width: openRect.width, height: openRect.height * 0.45))
                ctx.restoreGState()
            case .mouthFlat:
                ctx.setStrokeColor(colors.eyeDark)
                ctx.setLineWidth(size.height * 0.32)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: center.x - size.width * 0.5, y: center.y - size.height * 0.1))
                ctx.addLine(to: CGPoint(x: center.x + size.width * 0.5, y: center.y - size.height * 0.1))
                ctx.strokePath()
            default:
                break
            }
        case .blushBoost:
            for blush in [Self.blushLeft, Self.blushRight] {
                let center = blush.point(in: rect)
                let radius = CGFloat(blush.rx) * rect.width
                let gradient = CGGradient(
                    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                    colors: [colors.blush.copy(alpha: 0.55) ?? colors.blush,
                             colors.blush.copy(alpha: 0) ?? colors.blush] as CFArray,
                    locations: [0, 1]
                )!
                ctx.setBlendMode(.sourceAtop)
                ctx.drawRadialGradient(gradient, startCenter: center, startRadius: radius * 0.2,
                                       endCenter: center, endRadius: radius * 1.25, options: [])
                ctx.setBlendMode(.normal)
            }
        }
    }

    // MARK: - Debug export

    /// Writes every animation's baked frames as PNGs for visual review.
    static func exportFrames(to directory: URL, palette: CharacterPalette = .standard(for: .classicCream)) {
        let source = ReferenceImageSource()
        guard let base = loadArtwork() else {
            print("exportFrames: artwork not found"); return
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let colors = source.sampleColors(from: base)
        let canvas = CookieSpriteRenderer.canvasSize
        for animation in CookieAnimationId.allCases {
            guard let plan = plan(for: animation) else { continue }
            for (index, frame) in plan.enumerated() {
                let image = source.bake(frame: frame, base: base, colors: colors,
                                        canvas: canvas, palette: palette)
                let url = directory.appendingPathComponent("\(animation.rawValue)-\(index).png")
                let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
                if let dest {
                    CGImageDestinationAddImage(dest, image, nil)
                    CGImageDestinationFinalize(dest)
                }
            }
        }
    }
}
