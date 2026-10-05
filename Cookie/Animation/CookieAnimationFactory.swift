import SpriteKit

/// Building blocks for Cookie's idle loop and reactions. Timing is tuned
/// to feel soft and alive rather than mechanical.
enum CookieAnimationFactory {
    /// Gentle vertical drift, like quiet breathing.
    static func breathing() -> SKAction {
        let up = SKAction.moveBy(x: 0, y: 3, duration: 1.4)
        up.timingMode = .easeInEaseOut
        let down = SKAction.moveBy(x: 0, y: -3, duration: 1.4)
        down.timingMode = .easeInEaseOut
        return .repeatForever(.sequence([up, down]))
    }

    /// Lazy tail wag, pivoting around the tail's attachment point.
    static func tailSway() -> SKAction {
        let left = SKAction.rotate(byAngle: -.pi / 12, duration: 1.0)
        left.timingMode = .easeInEaseOut
        let right = SKAction.rotate(byAngle: .pi / 12, duration: 1.0)
        right.timingMode = .easeInEaseOut
        return .repeatForever(.sequence([left, right]))
    }

    /// Randomized blinking; `withRange` re-rolls the pause each cycle.
    static func blinking() -> SKAction {
        let pause = SKAction.wait(forDuration: 3.0, withRange: 3.5)
        let close = SKAction.scaleY(to: 0.12, duration: 0.07)
        let hold = SKAction.wait(forDuration: 0.06)
        let open = SKAction.scaleY(to: 1.0, duration: 0.08)
        return .repeatForever(.sequence([pause, close, hold, open]))
    }

    /// Squash-and-stretch hop used when Cookie is petted.
    static func hop() -> SKAction {
        let squash = SKAction.group([
            SKAction.scaleX(to: 1.12, duration: 0.10),
            SKAction.scaleY(to: 0.88, duration: 0.10)
        ])
        squash.timingMode = .easeOut

        let rise = SKAction.group([
            SKAction.moveBy(x: 0, y: 16, duration: 0.20),
            SKAction.scaleX(to: 0.92, duration: 0.20),
            SKAction.scaleY(to: 1.10, duration: 0.20)
        ])
        rise.timingMode = .easeOut

        let fall = SKAction.group([
            SKAction.moveBy(x: 0, y: -16, duration: 0.16),
            SKAction.scaleX(to: 1.08, duration: 0.16),
            SKAction.scaleY(to: 0.94, duration: 0.16)
        ])
        fall.timingMode = .easeIn

        let settle = SKAction.group([
            SKAction.scaleX(to: 1.0, duration: 0.14),
            SKAction.scaleY(to: 1.0, duration: 0.14)
        ])
        settle.timingMode = .easeOut

        return .sequence([squash, rise, fall, settle])
    }

    /// One slow glance to the side while watching the desktop.
    static func glance() -> SKAction {
        let across = SKAction.moveBy(x: 5, y: 0, duration: 0.5)
        across.timingMode = .easeInEaseOut
        let hold = SKAction.wait(forDuration: 1.2)
        let back = SKAction.moveBy(x: -5, y: 0, duration: 0.5)
        back.timingMode = .easeInEaseOut
        return .sequence([across, hold, back])
    }
}
