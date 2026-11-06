import AppKit
import SpriteKit
import os

/// Loads animation frames from sprite sheets in the application bundle.
///
/// Resource layout (see Resources/Sprites/README.md):
///
///     Sprites/Cookie/<Category>/<sheetName>.png        uniform grid sheet
///     Sprites/Cookie/<Category>/<sheetName>.json       optional manifest
///     Sprites/Cookie/<Category>/<sheetName>/frameN.png  or numbered frames
///
/// The manifest may override fps, looping, and frame order:
///
///     { "fps": 8, "loop": false, "frames": [0, 1, 2, 1], "grid": [4, 2] }
///
/// Grid sheets are sliced with `SKTexture(rectIn:)`, so the whole sheet
/// stays one GPU texture regardless of frame count. Results are cached.
///
/// Fur color and body shape are baked into a recolored copy of each sheet.
/// Coat patterns and eye customization only line up with the unmoving base
/// painting, so animations drawn from it step aside when those are in use and
/// the reference source renders them instead. Whole-pose animations keep their
/// own painted faces, matching how expression stickers behave.
@MainActor
final class SpriteSheetSource: AnimationFrameSource {
    private struct SheetManifest: Codable {
        var fps: Double?
        var loop: Bool?
        var frames: [Int]?
        var grid: [Int]?
    }

    /// A loaded animation: its textures plus any manifest overrides.
    private struct LoadedAnimation {
        var textures: [SKTexture]
        var manifest: SheetManifest?
        /// The source sheet, kept only for grid sheets so it can be recolored.
        var sheetImage: CGImage?
        var grid: (columns: Int, rows: Int)?
    }

    private static let log = Logger(subsystem: "com.cookie.mac", category: "Sprites")
    static let rootDirectory = "Sprites/Cookie"

    private let bundle: Bundle
    private var cache: [String: LoadedAnimation?] = [:]
    private var tintedCache: [String: [SKTexture]] = [:]

    /// Animations painted from the base artwork, which can show patterns and eye styles.
    static let baseArtAnimations: Set<CookieAnimationId> = [
        .idle, .idleBlink, .sit, .stretch, .yawn, .tired, .meow, .curious, .investigate, .jump, .pickedUp
    ]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Looks a sheet up without rendering it. Used to answer "does final
    /// artwork exist for this animation?" without touching the cache.
    func hasSheet(for animation: CookieAnimationId) -> Bool {
        load(animation) != nil
    }

    func textures(for animation: CookieAnimationId, config: CookieAppearanceConfig) -> [SKTexture]? {
        if Self.baseArtAnimations.contains(animation), Self.hasFaceOrCoatCustomization(config) {
            return nil
        }
        guard let loaded = load(animation) else { return nil }
        let bodyScale = config.bodyVariation.scale
        guard config.furColor.multiplyColor != nil || bodyScale.x != 1 || bodyScale.y != 1 else {
            return loaded.textures
        }
        guard let source = loaded.sheetImage, let grid = loaded.grid else { return loaded.textures }

        let key = "\(animation.spec.category.rawValue)/\(animation.spec.sheetName)|\(config.furColor.rawValue)|\(config.bodyVariation.rawValue)"
        if let cached = tintedCache[key] { return cached }
        guard let tinted = Self.tint(source, grid: grid, config: config) else { return loaded.textures }
        let textures = sliced(tinted, manifest: loaded.manifest).textures
        tintedCache[key] = textures
        return textures
    }

    func frameRate(for animation: CookieAnimationId) -> Double? {
        load(animation)?.manifest?.fps
    }

    private static func hasFaceOrCoatCustomization(_ config: CookieAppearanceConfig) -> Bool {
        config.furPattern != .none || config.eyeColor.renderColor != nil || config.eyeStyle != .round
    }

    /// Multiplies fur color over a sheet and scales each cell around its feet,
    /// the same way the reference source treats its frames.
    private static func tint(_ sheet: CGImage, grid: (columns: Int, rows: Int), config: CookieAppearanceConfig) -> CGImage? {
        let width = sheet.width
        let height = sheet.height
        func makeContext() -> CGContext? {
            CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }

        guard let shaped = makeContext() else { return nil }
        shaped.interpolationQuality = .high
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        let scale = config.bodyVariation.scale
        let cellWidth = CGFloat(width) / CGFloat(grid.columns)
        let cellHeight = CGFloat(height) / CGFloat(grid.rows)
        for row in 0..<grid.rows {
            for column in 0..<grid.columns {
                let cell = CGRect(x: CGFloat(column) * cellWidth, y: CGFloat(row) * cellHeight,
                                  width: cellWidth, height: cellHeight)
                shaped.saveGState()
                shaped.clip(to: cell)
                shaped.translateBy(x: cell.midX, y: cell.minY)
                shaped.scaleBy(x: scale.x, y: scale.y)
                shaped.translateBy(x: -cell.midX, y: -cell.minY)
                shaped.draw(sheet, in: full)
                shaped.restoreGState()
            }
        }
        guard let shapedImage = shaped.makeImage() else { return nil }
        guard let multiply = config.furColor.multiplyColor else { return shapedImage }

        guard let tinted = makeContext() else { return nil }
        tinted.draw(shapedImage, in: full)
        tinted.setBlendMode(.multiply)
        tinted.setFillColor(multiply)
        tinted.fill(full)
        tinted.setBlendMode(.destinationIn)
        tinted.draw(shapedImage, in: full)
        return tinted.makeImage()
    }

    /// Frame count sanity cap so a malformed manifest cannot exhaust
    /// memory by slicing a huge sheet thousands of times.
    private static let maxFrames = 64

    private func load(_ animation: CookieAnimationId) -> LoadedAnimation? {
        let spec = animation.spec
        let key = "\(spec.category.rawValue)/\(spec.sheetName)"
        if let cached = cache[key] {
            return cached
        }
        let loaded = loadUncached(animation)
        cache[key] = loaded
        if loaded == nil {
            Self.log.debug("No sheet for \(key, privacy: .public) — will use placeholder frames")
        }
        return loaded
    }

    private func loadUncached(_ animation: CookieAnimationId) -> LoadedAnimation? {
        let spec = animation.spec
        let baseDir = "\(Self.rootDirectory)/\(spec.category.rawValue)"
        let candidateDirectories = [
            baseDir,
            "\(baseDir)/\(spec.sheetName)",
            "\(baseDir)/\(spec.sheetName.capitalized)"
        ]

        var manifest: SheetManifest?
        for directory in candidateDirectories {
            if let manifestURL = bundle.url(forResource: spec.sheetName, withExtension: "json", subdirectory: directory)
                ?? bundle.url(forResource: "manifest", withExtension: "json", subdirectory: directory),
               let data = try? Data(contentsOf: manifestURL) {
                manifest = try? JSONDecoder().decode(SheetManifest.self, from: data)
                if manifest != nil { break }
            }
        }

        for directory in candidateDirectories {
            let names = [spec.sheetName, spec.sheetName.capitalized, "sheet"]
            for name in names {
                if let sheetURL = bundle.url(forResource: name, withExtension: "png", subdirectory: directory),
                   let image = NSImage(contentsOf: sheetURL),
                   let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    var loaded = sliced(cgImage, manifest: manifest)
                    loaded.sheetImage = cgImage
                    loaded.grid = (max(1, manifest?.grid?.first ?? 1), max(1, manifest?.grid?.last ?? 1))
                    Self.log.info("Loaded sheet \(spec.category.rawValue, privacy: .public)/\(spec.sheetName, privacy: .public): \(loaded.textures.count) frames")
                    return loaded
                }
            }
        }

        for directory in candidateDirectories {
            var frames: [SKTexture] = []
            for index in 0..<Self.maxFrames where frames.count < Self.maxFrames {
                guard let url = bundle.url(forResource: "frame\(index)", withExtension: "png", subdirectory: directory),
                      let image = NSImage(contentsOf: url),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { break }
                frames.append(SKTexture(cgImage: cgImage))
            }
            if !frames.isEmpty {
                if let order = manifest?.frames {
                    frames = order.compactMap { frames.indices.contains($0) ? frames[$0] : nil }
                }
                return LoadedAnimation(textures: frames, manifest: manifest)
            }
        }
        return nil
    }

    private func sliced(_ cgImage: CGImage, manifest: SheetManifest?) -> LoadedAnimation {
        let sheet = SKTexture(cgImage: cgImage)
        let columns = manifest?.grid?.first ?? 1
        let rows = manifest?.grid?.last ?? 1
        let columnCount = max(1, columns)
        let rowCount = max(1, rows)
        let total = min(Self.maxFrames, columnCount * rowCount)

        let order = manifest?.frames ?? Array(0..<total)
        var textures: [SKTexture] = []
        for index in order where index >= 0 && index < total {
            let column = index % columnCount
            let rowFromTop = index / columnCount
            let width = 1.0 / CGFloat(columnCount)
            let height = 1.0 / CGFloat(rowCount)
            // SpriteKit texture rects use a bottom-left origin; sheet
            // frame numbers count from the top-left.
            let rect = CGRect(
                x: CGFloat(column) * width,
                y: 1.0 - CGFloat(rowFromTop + 1) * height,
                width: width,
                height: height
            )
            textures.append(SKTexture(rect: rect, in: sheet))
        }
        return LoadedAnimation(textures: textures, manifest: manifest)
    }
}
