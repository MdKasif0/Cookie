import AppKit
import SpriteKit

/// Loads the rendered art under Sprites/Cookie: toys and treats, accessories, and icons.
/// See scripts/render_items_3d.py.
@MainActor
enum CookieArtwork {
    private static var images: [String: NSImage] = [:]

    static func image(_ folder: String, _ name: String) -> NSImage? {
        let key = "\(folder)/\(name)"
        if let cached = images[key] { return cached }
        guard let url = Bundle.main.url(
            forResource: name, withExtension: "png",
            subdirectory: "\(SpriteSheetSource.rootDirectory)/\(folder)"
        ), let image = NSImage(contentsOf: url) else { return nil }
        images[key] = image
        return image
    }

    static func texture(_ folder: String, _ name: String) -> SKTexture? {
        image(folder, name).map { SKTexture(image: $0) }
    }

    /// An icon sized for a menu row.
    static func menuIcon(_ name: String) -> NSImage? {
        guard let source = image("Icons", name)?.copy() as? NSImage else { return nil }
        source.size = NSSize(width: 18, height: 18)
        return source
    }

    /// The frames of a sprite sheet as individual images, plus its frame rate.
    static func frames(category: String, sheet: String) -> (images: [NSImage], fps: Double)? {
        struct Manifest: Decodable {
            let grid: [Int]
            let fps: Double
            let frames: [Int]?
        }
        let directory = "\(SpriteSheetSource.rootDirectory)/\(category)"
        guard let manifestURL = Bundle.main.url(forResource: sheet, withExtension: "json", subdirectory: directory),
              let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.grid.count == 2, manifest.grid[0] > 0, manifest.grid[1] > 0,
              let imageURL = Bundle.main.url(forResource: sheet, withExtension: "png", subdirectory: directory),
              let source = NSImage(contentsOf: imageURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }

        let columns = manifest.grid[0]
        let rows = manifest.grid[1]
        let cellWidth = source.width / columns
        let cellHeight = source.height / rows
        let order = manifest.frames ?? Array(0..<(columns * rows))
        let frames = order.compactMap { cell -> NSImage? in
            guard cell >= 0, cell < columns * rows else { return nil }
            let area = CGRect(x: cell % columns * cellWidth, y: cell / columns * cellHeight,
                              width: cellWidth, height: cellHeight)
            return source.cropping(to: area).map {
                NSImage(cgImage: $0, size: NSSize(width: cellWidth / 2, height: cellHeight / 2))
            }
        }
        return frames.isEmpty ? nil : (frames, manifest.fps)
    }
}
