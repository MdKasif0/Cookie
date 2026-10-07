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

    // Measured from the shipped artwork by scripts/analyze_reference.swift
    // and scripts/probe reference runs — update these together with the
    // CookieArt asset.
    private static let eyeLeft = Feature(x: 0.283, y: 0.395, rx: 0.052, ry: 0.049)
    private static let eyeRight = Feature(x: 0.646, y: 0.438, rx: 0.053, ry: 0.049)
    private static let mouth = Feature(x: 0.450, y: 0.464, rx: 0.059, ry: 0.023)
    private static let blushLeft = Feature(x: 0.170, y: 0.470, rx: 0.075, ry: 0.075)
    private static let blushRight = Feature(x: 0.740, y: 0.525, rx: 0.072, ry: 0.072)

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
        case .investigate:
            return [
                Frame(scaleX: 1.02, scaleY: 0.96, offsetX: 3, offsetY: 2, overlays: [.eyesWide]),
                Frame(scaleX: 1.03, scaleY: 0.94, offsetX: 4, offsetY: 3, overlays: [.eyesWide]),
                Frame(scaleX: 1.02, scaleY: 0.96, offsetX: 3, offsetY: 2, overlays: [.eyesWide])
            ]
        case .tired:
            return [
                Frame(scaleY: 0.94, offsetY: 2, overlays: [.eyesHalf, .mouthFlat]),
                Frame(scaleY: 0.92, offsetY: 3, overlays: [.eyesHappy, .mouthFlat])
            ]
        case .inBox:
            return [
                Frame(scaleY: 0.9, offsetY: 8, overlays: [.eyesHalf]),
                Frame(scaleY: 0.88, offsetY: 9, overlays: [.eyesClosed])
            ]
        case .boxPeek:
            return [
                Frame(scaleY: 0.98, offsetY: -2, overlays: [.eyesWide]),
                Frame(scaleY: 1.01, offsetY: -3, overlays: [.eyesHappy])
            ]
        }
    }

    // MARK: - Baking

    private let cache = NSCache<NSString, NSArray>()
    private var sampledColors: SampledColors?

    func textures(for animation: CookieAnimationId, config: CookieAppearanceConfig) -> [SKTexture]? {
        guard let base = Self.loadArtwork(), let plan = Self.plan(for: animation) else { return nil }
        let colors = sampleColors(from: base)
        let key = "\(config.renderKey)|\(animation.rawValue)" as NSString
        if let cached = cache.object(forKey: key) {
            return cached as? [SKTexture]
        }
        let canvas = CookieSpriteRenderer.canvasSize
        let textures = plan.map { frame in
            SKTexture(cgImage: bake(frame: frame, base: base, colors: colors,
                                    canvas: canvas, config: config))
        }
        cache.setObject(textures as NSArray, forKey: key)
        return textures
    }

    static func loadArtwork() -> CGImage? {
        guard let image = NSImage(named: NSImage.Name(Self.artName)) else { return nil }
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    /// Fits an image of the given aspect into the canvas, anchored to the
    /// bottom so poses feel grounded. Shared with the expression stickers.
    static func fitRect(aspect: Double, canvas: CGSize) -> CGRect {
        let inset = canvas.width * 0.02
        let available = CGSize(width: canvas.width - inset * 2, height: canvas.height - inset * 1.5)
        let canvasAspect = available.width / available.height
        var size = available
        if aspect > canvasAspect {
            size.height = available.width / aspect
        } else {
            size.width = available.height * aspect
        }
        return CGRect(
            x: (canvas.width - size.width) / 2,
            y: inset * 0.4,
            width: size.width,
            height: size.height
        )
    }

    /// The draw rect for the base artwork inside the canvas.
    static func artRect(canvas: CGSize) -> CGRect {
        fitRect(aspect: imageAspect, canvas: canvas)
    }

    /// Aspect of the shipped artwork, measured once from the asset.
    private static let imageAspect: Double = {
        guard let image = loadArtwork() else { return 1050.0 / 1158.0 }
        return Double(image.width) / Double(image.height)
    }()

    private func bake(frame: Frame, base: CGImage, colors: SampledColors,
                      canvas: CGSize, config: CookieAppearanceConfig) -> CGImage {
        let scale = Self.bakeScale
        let pixels = CGSize(width: canvas.width * scale, height: canvas.height * scale)

        // Pass 1: the transformed, customized cat on a transparent canvas.
        let pass = CGContext(
            data: nil, width: Int(pixels.width), height: Int(pixels.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        pass.scaleBy(x: scale, y: scale)
        pass.interpolationQuality = .high

        let rect = Self.artRect(canvas: canvas)
        // Anchor at the feet: bottom center of the artwork.
        let anchor = CGPoint(x: rect.midX, y: rect.minY)
        pass.saveGState()
        pass.translateBy(x: anchor.x, y: anchor.y)
        pass.rotate(by: frame.rotation * .pi / 180)
        pass.scaleBy(x: frame.scaleX * config.bodyVariation.scale.x,
                     y: frame.scaleY * config.bodyVariation.scale.y)
        pass.translateBy(x: -anchor.x, y: -anchor.y - frame.offsetY)
        let drawRect = rect.offsetBy(dx: frame.offsetX, dy: frame.offsetY)

        pass.draw(base, in: drawRect)

        for overlay in frame.overlays {
            drawOverlay(overlay, in: pass, base: base, rect: drawRect, colors: colors,
                        eyeFill: config.eyeColor.renderColor ?? colors.eyeDark)
        }

        drawPattern(config.furPattern, in: pass, rect: drawRect)
        drawEyeCustomization(frame: frame, config: config, in: pass, rect: drawRect, colors: colors)
        pass.restoreGState()

        guard let catImage = pass.makeImage() else { return base }

        // Pass 2: fur color as a multiply tint over the whole canvas, then
        // a destination-in pass with the full-canvas cat restores the exact
        // silhouette — multiply scales luminance instead of washing over
        // it, so the artwork's contrast is preserved.
        let ctx = CGContext(
            data: nil, width: Int(pixels.width), height: Int(pixels.height),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.interpolationQuality = .high
        ctx.draw(catImage, in: CGRect(origin: .zero, size: pixels))

        if let multiply = config.furColor.multiplyColor {
            ctx.setBlendMode(.multiply)
            ctx.setFillColor(multiply)
            ctx.fill(CGRect(origin: .zero, size: pixels))
            ctx.setBlendMode(.destinationIn)
            ctx.draw(catImage, in: CGRect(origin: .zero, size: pixels))
            ctx.setBlendMode(.normal)
        }

        return ctx.makeImage() ?? base
    }

    // MARK: - Pattern & eyes

    /// Soft coat patterns, drawn only where the cat is.
    private func drawPattern(_ pattern: FurPattern, in ctx: CGContext, rect: CGRect) {
        switch pattern {
        case .none:
            return
        case .tuxedo:
            // A gently darker chest patch.
            let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.24)
            softSpot(ctx, center: center, radiusX: rect.width * 0.30, radiusY: rect.height * 0.20,
                     color: CGColor(srgbRed: 0.72, green: 0.62, blue: 0.52, alpha: 0.30))
        case .points:
            // A softly darker face mask, like a pointed coat.
            let center = CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY + rect.height * 0.80)
            softSpot(ctx, center: center, radiusX: rect.width * 0.40, radiusY: rect.height * 0.22,
                     color: CGColor(srgbRed: 0.70, green: 0.60, blue: 0.50, alpha: 0.24))
        case .tabby:
            // Three little forehead stripes.
            ctx.setBlendMode(.sourceAtop)
            ctx.setStrokeColor(CGColor(srgbRed: 0.66, green: 0.53, blue: 0.38, alpha: 0.45))
            ctx.setLineWidth(rect.width * 0.035)
            ctx.setLineCap(.round)
            for (offset, length) in [(0.0, 0.09), (-0.075, 0.06), (0.075, 0.06)] {
                let x = rect.minX + rect.width * (0.46 + offset)
                let yTop = rect.minY + rect.height * 0.86
                ctx.move(to: CGPoint(x: x, y: yTop))
                ctx.addLine(to: CGPoint(x: x + rect.width * 0.012, y: yTop - rect.height * length))
            }
            ctx.strokePath()
            ctx.setBlendMode(.normal)
        }
    }

    private func softSpot(_ ctx: CGContext, center: CGPoint, radiusX: CGFloat, radiusY: CGFloat, color: CGColor) {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let gradient = CGGradient(colorsSpace: space, colors: [
            color, color.copy(alpha: color.alpha * 0.6) ?? color, color.copy(alpha: 0) ?? color
        ] as CFArray, locations: [0, 0.55, 1])!
        ctx.setBlendMode(.sourceAtop)
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: radiusX, y: radiusY)
        ctx.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                               endCenter: .zero, endRadius: 1, options: [])
        ctx.restoreGState()
        ctx.setBlendMode(.normal)
    }

    /// Eye color and eye style, applied to the base pose when the eyes
    /// are actually visible. Expression stickers never get these.
    private func drawEyeCustomization(frame: Frame, config: CookieAppearanceConfig,
                                      in ctx: CGContext, rect: CGRect, colors: SampledColors) {
        let eyesCovered = !frame.overlays.contains { overlay in
            switch overlay {
            case .eyesClosed, .eyesHappy, .eyesWide, .eyesHalf: return true
            default: return false
            }
        }

        // Color: repaint the open eyes and redraw the glints.
        if eyesCovered == false, let eyeFill = config.eyeColor.renderColor {
            for eye in [Self.eyeLeft, Self.eyeRight] {
                let center = eye.point(in: rect)
                let size = eye.scaledSize(in: rect)
                ctx.setFillColor(eyeFill)
                ctx.fillEllipse(in: CGRect(
                    x: center.x - size.width * 0.52, y: center.y - size.height * 0.52,
                    width: size.width * 1.04, height: size.height * 1.04
                ))
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96))
                ctx.fillEllipse(in: CGRect(
                    x: center.x - size.width * 0.42, y: center.y + size.height * 0.02,
                    width: size.width * 0.40, height: size.height * 0.40
                ))
                ctx.fillEllipse(in: CGRect(
                    x: center.x + size.width * 0.12, y: center.y - size.height * 0.30,
                    width: size.width * 0.20, height: size.height * 0.20
                ))
            }
        }

        switch config.eyeStyle {
        case .round:
            break
        case .sleepy where eyesCovered == false:
            for eye in [Self.eyeLeft, Self.eyeRight] {
                let center = eye.point(in: rect)
                let size = eye.scaledSize(in: rect)
                softSpot(ctx, center: CGPoint(x: center.x, y: center.y + size.height * 0.62),
                         radiusX: size.width * 0.95, radiusY: size.height * 0.78,
                         color: colors.fur)
                ctx.setStrokeColor(colors.eyeDark)
                ctx.setLineWidth(size.height * 0.16)
                ctx.setLineCap(.round)
                ctx.move(to: CGPoint(x: center.x - size.width * 0.5, y: center.y + size.height * 0.18))
                ctx.addLine(to: CGPoint(x: center.x + size.width * 0.5, y: center.y + size.height * 0.18))
                ctx.strokePath()
            }
        case .sparkle where eyesCovered == false:
            for eye in [Self.eyeLeft, Self.eyeRight] {
                let center = eye.point(in: rect)
                let size = eye.scaledSize(in: rect)
                ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
                ctx.fillEllipse(in: CGRect(
                    x: center.x + size.width * 0.08, y: center.y - size.height * 0.05,
                    width: size.width * 0.26, height: size.height * 0.26
                ))
                ctx.fillEllipse(in: CGRect(
                    x: center.x - size.width * 0.30, y: center.y - size.height * 0.42,
                    width: size.width * 0.16, height: size.height * 0.16
                ))
            }
        default:
            break
        }
    }

    // MARK: - Overlays

    private struct SampledColors {
        var eyeDark: CGColor
        var blush: CGColor
        var fur: CGColor
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
            sampledColors = SampledColors(eyeDark: fallback, blush: fallback, fur: fallback)
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
            blush: probe(Self.blushLeft.x, Self.blushLeft.y),
            fur: probe(0.50, 0.68)
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

    private func drawOverlay(_ overlay: Overlay, in ctx: CGContext, base: CGImage, rect: CGRect, colors: SampledColors, eyeFill: CGColor) {
        switch overlay {
        case .eyesClosed, .eyesHappy, .eyesWide, .eyesHalf:
            for eye in [Self.eyeLeft, Self.eyeRight] {
                let center = eye.point(in: rect)
                let size = eye.scaledSize(in: rect)
                // Clone from the bridge between the eyes: at eye height,
                // so its shading matches the area being covered.
                let sourceNorm = CGPoint(x: 0.46, y: 0.36)
                switch overlay {
                case .eyesClosed:
                    let patch = CGSize(width: size.width * 2.0, height: size.height * 1.35)
                    cloneOver(ctx, base: base, rect: rect, over: center,
                              patchSize: patch, sourceCenterNorm: sourceNorm)
                    strokeEyeArc(ctx, at: CGPoint(x: center.x, y: center.y + size.height * 0.12),
                                 radius: size.width * 0.62, upper: false,
                                 color: colors.eyeDark, width: size.height * 0.22)
                case .eyesHappy:
                    let patch = CGSize(width: size.width * 2.0, height: size.height * 1.35)
                    cloneOver(ctx, base: base, rect: rect, over: center,
                              patchSize: patch, sourceCenterNorm: sourceNorm)
                    strokeEyeArc(ctx, at: CGPoint(x: center.x, y: center.y - size.height * 0.08),
                                 radius: size.width * 0.62, upper: true,
                                 color: colors.eyeDark, width: size.height * 0.22)
                case .eyesWide:
                    let patch = CGSize(width: size.width * 1.6, height: size.height * 1.6)
                    cloneOver(ctx, base: base, rect: rect, over: center,
                              patchSize: patch, sourceCenterNorm: sourceNorm)
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
                              patchSize: patch, sourceCenterNorm: sourceNorm)
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
    static func exportFrames(to directory: URL, config: CookieAppearanceConfig = CookieAppearanceConfig()) {
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
                                        canvas: canvas, config: config)
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
