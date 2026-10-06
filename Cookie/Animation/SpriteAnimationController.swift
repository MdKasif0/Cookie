import Foundation
import SpriteKit
import os

/// Drives Cookie's frame animation: resolves textures from an ordered
/// chain of sources, plays them through a single sprite node, and
/// arbitrates competing animations with a priority system.
///
/// Rules:
/// - One looping "base" animation (idle, sit, curious, walk…) is always
///   defined; a one-shot (pet, stretch, meow…) plays over it and, when it
///   finishes, the previous base resumes automatically.
/// - A higher-priority animation interrupts a lower one; equal priorities
///   only interrupt looping animations (so idleBlink plays over idle but
///   never cuts off a pet reaction).
/// - An animation whose artwork is missing falls back to idle rather than
///   failing, so the catalog can grow ahead of the artwork.
/// - With Reduced Motion enabled, transitions still happen and callbacks
///   still fire, but poses render statically.
@MainActor
final class SpriteAnimationController {
    private let sprite: SKSpriteNode
    private let flipContainer: SKNode
    private var sources: [AnimationFrameSource]
    private var palette: CharacterPalette

    private let log = Logger(subsystem: "com.cookie.mac", category: "Animation")
    private var warnedMissing: Set<String> = []

    // State machine
    private(set) var currentId: CookieAnimationId?
    private var currentPriority: CookieAnimationPriority = .idle
    private var currentIsLoop = true
    private var currentCompletion: ((Bool) -> Void)?
    private var baseId: CookieAnimationId = .idle
    private var pendingBase: CookieAnimationId?
    private(set) var facing: CookieDirection = .right

    // Timers
    private var blinkTimer: Timer?
    private var staticHoldTimer: Timer?

    init(
        sprite: SKSpriteNode,
        flipContainer: SKNode,
        palette: CharacterPalette,
        sources: [AnimationFrameSource]
    ) {
        self.sprite = sprite
        self.flipContainer = flipContainer
        self.palette = palette
        self.sources = sources
    }

    // MARK: - Public API

    /// Sets the looping animation Cookie returns to after one-shots.
    func setBase(_ id: CookieAnimationId) {
        let spec = id.spec
        if let direction = spec.direction {
            setFacing(direction)
        }
        baseId = id
        pendingBase = nil

        if let current = currentId, !current.spec.isLooping, current.spec.priority > spec.priority {
            // A more forceful one-shot is playing; wait for it to finish.
            pendingBase = id
            return
        }
        if currentId == id, currentIsLoop {
            return
        }
        interruptCurrent()
        present(id)
    }

    /// Plays an animation, subject to the priority rules. Returns false
    /// (and calls the completion with `false`) when a playing animation
    /// outranks it. Non-looping animations call the completion with
    /// `true` when they finish naturally.
    @discardableResult
    func play(_ id: CookieAnimationId, completion: ((Bool) -> Void)? = nil) -> Bool {
        let spec = id.spec
        if let direction = spec.direction {
            setFacing(direction)
        }
        if currentId == id {
            completion?(false)
            return true
        }
        let mayPlay = currentId == nil
            || spec.priority > currentPriority
            || (spec.priority == currentPriority && currentIsLoop && !spec.isLooping)
        guard mayPlay else {
            log.debug("\(id.rawValue, privacy: .public) outranked by \(self.currentId?.rawValue ?? "?", privacy: .public)")
            completion?(false)
            return false
        }
        interruptCurrent()
        present(id, completion: completion)
        return true
    }

    func setFacing(_ direction: CookieDirection) {
        guard facing != direction else { return }
        facing = direction
        // Mirroring a centered sprite needs no separate left/right sheets.
        flipContainer.xScale = direction == .left ? -1 : 1
    }

    /// Re-renders the current animation, e.g. after a palette change.
    func refresh() {
        guard let id = currentId else { return }
        present(id, completion: currentCompletion)
    }

    /// Switches the palette. Rendered placeholder textures are dropped so
    /// the next frame of every animation reflects the new colors; bundle
    /// sheets are untouched by palettes.
    func updatePalette(_ palette: CharacterPalette) {
        self.palette = palette
        for source in sources {
            (source as? PlaceholderVectorSource)?.invalidate()
        }
    }

    // MARK: - Playback internals

    private func present(_ id: CookieAnimationId, completion: ((Bool) -> Void)? = nil) {
        let spec = id.spec
        guard let textures = resolveTextures(id) else {
            // Even idle artwork is missing: keep the last frame visible
            // and treat the request as finished.
            log.error("No artwork at all for \(id.rawValue, privacy: .public)")
            completion?(false)
            return
        }

        cancelTimers()
        sprite.removeAction(forKey: CookieAnimationId.actionKey)
        currentId = id
        currentPriority = spec.priority
        currentIsLoop = spec.isLooping
        currentCompletion = completion

        let frameDuration = 1.0 / spec.fps
        if MotionSettings.reduceMotion {
            sprite.texture = textures.first
            if !spec.isLooping {
                let hold = max(0.4, Double(textures.count) * frameDuration * 0.6)
                staticHoldTimer = Timer.scheduledTimer(withTimeInterval: hold, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.finishOneShot()
                    }
                }
            }
            return
        }

        let animate = SKAction.animate(
            with: textures,
            timePerFrame: frameDuration,
            resize: false,
            restore: false
        )
        if spec.isLooping {
            sprite.run(.repeatForever(animate), withKey: CookieAnimationId.actionKey)
        } else {
            let finish = SKAction.run { [weak self] in
                self?.finishOneShot()
            }
            sprite.run(.sequence([animate, finish]), withKey: CookieAnimationId.actionKey)
        }
        scheduleBlinkIfNeeded()
    }

    private func finishOneShot() {
        guard let id = currentId, !currentIsLoop else { return }
        currentId = nil
        let completion = currentCompletion
        currentCompletion = nil
        completion?(true)
        log.debug("\(id.rawValue, privacy: .public) finished → \(self.baseId.rawValue, privacy: .public)")
        let base = pendingBase ?? baseId
        pendingBase = nil
        present(base)
    }

    private func interruptCurrent() {
        guard currentId != nil else { return }
        cancelTimers()
        sprite.removeAction(forKey: CookieAnimationId.actionKey)
        currentId = nil
        let completion = currentCompletion
        currentCompletion = nil
        completion?(false)
    }

    // MARK: - Textures

    private func resolveTextures(_ id: CookieAnimationId) -> [SKTexture]? {
        for source in sources {
            if let textures = source.textures(for: id, palette: palette) {
                return textures
            }
        }
        if id == .idle {
            return nil
        }
        let key = id.spec.category.rawValue + "/" + id.rawValue
        if warnedMissing.insert(key).inserted {
            log.notice("No artwork for \(key, privacy: .public) — falling back to idle")
        }
        return resolveTextures(.idle)
    }

    // MARK: - Blinking

    /// While resting in idle or sit, occasionally blink. Blinking is a
    /// plain one-shot at idle priority: it never interrupts anything.
    private func scheduleBlinkIfNeeded() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        guard !MotionSettings.reduceMotion,
              currentIsLoop,
              currentPriority <= .idle,
              currentId == .idle || currentId == .sit else { return }
        blinkTimer = Timer.scheduledTimer(withTimeInterval: Double.random(in: 2.5...6.5), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.blinkTimer = nil
                if self?.currentId == .idle || self?.currentId == .sit {
                    self?.play(.idleBlink)
                }
            }
        }
    }

    private func cancelTimers() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        staticHoldTimer?.invalidate()
        staticHoldTimer = nil
    }
}
