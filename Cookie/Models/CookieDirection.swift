import Foundation

/// Which way Cookie faces. Directional animations mirror one shared
/// sheet instead of shipping separate left/right artwork.
enum CookieDirection: String, Codable {
    case left
    case right
}

/// Which vertical boundary Cookie is next to.
enum CookieEdge {
    case left
    case right
}
