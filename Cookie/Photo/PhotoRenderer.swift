import AppKit
import SpriteKit
import ImageIO
import UniformTypeIdentifiers

/// A pose offered in Photo Mode: one of Cookie's animations, shown as a still or a loop.
struct PhotoPose: Identifiable, Equatable {
    let id: String
    let title: String
    let animation: CookieAnimationId

    static let all: [PhotoPose] = [
        PhotoPose(id: "idle", title: "Sitting Pretty", animation: .idle),
        PhotoPose(id: "wave", title: "Hello!", animation: .wave),
        PhotoPose(id: "happy", title: "Happy", animation: .happyEmote),
        PhotoPose(id: "love", title: "In Love", animation: .love),
        PhotoPose(id: "playful", title: "Playful", animation: .playfulEmote),
        PhotoPose(id: "sleepy", title: "Sleepy", animation: .sleepy),
        PhotoPose(id: "napping", title: "Napping", animation: .sleep),
        PhotoPose(id: "walk", title: "On a Stroll", animation: .walkRight),
        PhotoPose(id: "curious", title: "Curious", animation: .curious),
        PhotoPose(id: "stretch", title: "Big Stretch", animation: .stretch)
    ]
}

enum PhotoBackdrop: String, CaseIterable, Identifiable {
    case transparent, cream, blush, sky, mint, night

    var id: String { rawValue }

    var title: String {
        switch self {
        case .transparent: return "Transparent"
        case .cream: return "Cream"
        case .blush: return "Blush"
        case .sky: return "Sky"
        case .mint: return "Mint"
        case .night: return "Night"
        }
    }

    /// The fill color, or nil to leave the background clear.
    var color: CGColor? {
        func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
            CGColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
        switch self {
        case .transparent: return nil
        case .cream: return srgb(0.98, 0.95, 0.89)
        case .blush: return srgb(0.98, 0.88, 0.86)
        case .sky: return srgb(0.84, 0.91, 0.97)
        case .mint: return srgb(0.86, 0.94, 0.88)
        case .night: return srgb(0.17, 0.18, 0.26)
        }
    }
}

/// Renders Cookie, as she looks right now, to images for sharing.
@MainActor
final class CookiePhotoRenderer {
    /// Frames are the app's 180pt canvas at 2x.
    static let frameSide = 360

    struct Clip {
        var frames: [CGImage]
        var fps: Double
        /// A single picture, for poses with nothing to animate.
        var isStill: Bool { frames.count <= 1 }
    }

    private let sheets = SpriteSheetSource()
    private let reference = ReferenceImageSource()
    private let placeholder = PlaceholderVectorSource()

    /// The frames of `pose` in her current look: fur, body, coat, eyes, accessories and today's outfit.
    func clip(for pose: PhotoPose, config: CookieAppearanceConfig, backdrop: PhotoBackdrop) -> Clip? {
        let animation = pose.animation
        let textures: [SKTexture]
        let fps: Double
        var showsAccessories = true

        // Older builds kept a single speech-bubble picture in the emote folders; that isn't an animation of her.
        if let fromSheet = sheets.textures(for: animation, config: config), fromSheet.count > 1 {
            textures = fromSheet
            fps = sheets.frameRate(for: animation) ?? animation.spec.fps
            // Sheets painted from other poses carry their own look, so accessories wouldn't line up.
            showsAccessories = SpriteSheetSource.baseArtAnimations.contains(animation)
        } else if let derived = reference.textures(for: animation, config: config) ?? placeholder.textures(for: animation, config: config) {
            textures = derived
            fps = animation.spec.fps
        } else {
            return nil
        }
        guard !textures.isEmpty else { return nil }

        // Some sheets repeat their frames to fill an emote's time on screen. A shared loop only needs one cycle.
        let cycle = Self.cycleLength(of: textures.map { $0.textureRect() })
        let frames = textures.prefix(cycle).compactMap { texture -> CGImage? in
            Self.composite(
                frame: texture.cgImage(),
                config: showsAccessories ? config : nil,
                backdrop: backdrop
            )
        }
        return frames.isEmpty ? nil : Clip(frames: frames, fps: fps)
    }

    /// The length of the shortest block that, repeated, makes up `items`.
    static func cycleLength<T: Equatable>(of items: [T]) -> Int {
        let count = items.count
        guard count > 1 else { return count }
        for length in 1...count where count % length == 0 {
            if (0..<count).allSatisfy({ items[$0] == items[$0 % length] }) { return length }
        }
        return count
    }

    /// One frame on its backdrop with accessories drawn over it, at the export size.
    static func composite(frame: CGImage, config: CookieAppearanceConfig?, backdrop: PhotoBackdrop) -> CGImage? {
        let side = frameSide
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        let full = CGRect(x: 0, y: 0, width: side, height: side)

        if let color = backdrop.color {
            context.setFillColor(color)
            context.fill(full)
        }
        context.draw(frame, in: full)

        if let config {
            for kind in CookieAccessoryLayer.drawOrder {
                let accessory = config.accessory(for: kind)
                guard accessory.isEnabled,
                      let art = CookieArtwork.image("Accessories", kind.rawValue)?
                        .cgImage(forProposedRect: nil, context: nil, hints: nil) else { continue }
                // Scale about the accessory's anchor, then nudge by its height setting.
                let anchor = kind.anchor
                let pivotX = anchor.x * CGFloat(side)
                let pivotY = (1 - anchor.y) * CGFloat(side)
                context.saveGState()
                context.translateBy(x: pivotX, y: pivotY + accessory.offsetY * CGFloat(side))
                context.scaleBy(x: accessory.scale, y: accessory.scale)
                context.translateBy(x: -pivotX, y: -pivotY)
                context.draw(art, in: full)
                context.restoreGState()
            }
        }
        return context.makeImage()
    }

    // MARK: - Encoding

    static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// An endlessly looping GIF. GIF only has fully clear or fully solid pixels, so soft edges on a
    /// transparent backdrop become hard; a solid backdrop keeps them smooth.
    static func gifData(_ clip: Clip) -> Data? {
        guard !clip.frames.isEmpty else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, clip.frames.count, nil) else { return nil }

        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]
        ] as CFDictionary)
        // GIF delays are in hundredths of a second, so round to the nearest the format can show.
        let delay = max(0.02, (1.0 / max(clip.fps, 1) * 100).rounded() / 100)
        for frame in clip.frames {
            CGImageDestinationAddImage(destination, frame, [
                kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]
            ] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { return nil }
        var bytes = data as Data
        // ImageIO labels the file GIF87a but uses animation and transparency blocks that belong to GIF89a.
        if bytes.starts(with: Array("GIF87a".utf8)) {
            bytes.replaceSubrange(0..<6, with: Array("GIF89a".utf8))
        }
        return bytes
    }
}
