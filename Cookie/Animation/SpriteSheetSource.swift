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
    }

    private static let log = Logger(subsystem: "com.cookie.mac", category: "Sprites")
    static let rootDirectory = "Sprites/Cookie"

    private let bundle: Bundle
    private var cache: [String: LoadedAnimation?] = [:]

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    /// Looks a sheet up without rendering it. Used to answer "does final
    /// artwork exist for this animation?" without touching the cache.
    func hasSheet(for animation: CookieAnimationId) -> Bool {
        load(animation) != nil
    }

    func textures(for animation: CookieAnimationId, palette: CharacterPalette) -> [SKTexture]? {
        load(animation)?.textures
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
        let directory = "\(Self.rootDirectory)/\(spec.category.rawValue)"

        var manifest: SheetManifest?
        if let manifestURL = bundle.url(forResource: spec.sheetName, withExtension: "json", subdirectory: directory),
           let data = try? Data(contentsOf: manifestURL) {
            manifest = try? JSONDecoder().decode(SheetManifest.self, from: data)
        }

        if let sheetURL = bundle.url(forResource: spec.sheetName, withExtension: "png", subdirectory: directory),
           let image = NSImage(contentsOf: sheetURL),
           let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return sliceSheet(cgImage, manifest: manifest, name: "\(spec.category.rawValue)/\(spec.sheetName)")
        }

        var frames: [SKTexture] = []
        for index in 0..<Self.maxFrames where frames.count < Self.maxFrames {
            guard let url = bundle.url(forResource: "frame\(index)", withExtension: "png", subdirectory: directory),
                  let image = NSImage(contentsOf: url),
                  let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { break }
            frames.append(SKTexture(cgImage: cgImage))
        }
        if frames.isEmpty {
            return nil
        }
        if let order = manifest?.frames {
            frames = order.compactMap { frames.indices.contains($0) ? frames[$0] : nil }
        }
        return LoadedAnimation(textures: frames, manifest: manifest)
    }

    private func sliceSheet(_ cgImage: CGImage, manifest: SheetManifest?, name: String) -> LoadedAnimation {
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
        Self.log.info("Loaded sheet \(name, privacy: .public): \(textures.count) frames")
        return LoadedAnimation(textures: textures, manifest: manifest)
    }
}
