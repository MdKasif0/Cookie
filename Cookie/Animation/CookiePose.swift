import Foundation

/// One rendered frame of the placeholder cat. Poses are parameter
/// variations of the same drawing, so the whole animation set stays
/// visually consistent and cheap to define.
struct CookiePose {
    var squash: CGFloat = 1
    var bodyY: CGFloat = 0
    var headX: CGFloat = 0
    var headY: CGFloat = 0
    var headTilt: CGFloat = 0
    var tailAngle: CGFloat = 0
    var pawOffsetX: CGFloat = 0
    var pawLift: CGFloat = 0
    var earStyle: CookieEarStyle = .normal
    var eyeStyle: CookieEyeStyle = .open
    var mouthStyle: CookieMouthStyle = .smile
    var blushScale: CGFloat = 1
    var gazeX: CGFloat = 0
}

enum CookieEyeStyle {
    case open
    case wide
    case half
    case happy
    case closed
}

enum CookieMouthStyle {
    case smile
    case flat
    case open
    case openWide
}

enum CookieEarStyle {
    case normal
    case back
}
