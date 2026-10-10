import Foundation
import CoreGraphics

/// Reusable delta-time driven movement interpolator providing smooth acceleration,
/// physical deceleration braking curves, distance-aware velocity profiles, and arrival thresholds.
final class MovementInterpolator {
    /// Maximum allowed translation speed in points per second.
    var maxSpeed: CGFloat

    /// Acceleration rate in points per second squared.
    var acceleration: CGFloat

    /// Deceleration braking rate in points per second squared.
    var deceleration: CGFloat

    /// Arrival threshold in points — closer than this snaps to target and zeroes velocity.
    var arrivalThreshold: CGFloat

    /// Current interpolated position.
    private(set) var currentPosition: CGFloat

    /// Current signed velocity in points per second.
    private(set) var currentVelocity: CGFloat = 0

    /// Desired destination position.
    private(set) var targetPosition: CGFloat

    /// Indicates whether the position has arrived at the target within threshold.
    private(set) var isArrived: Bool = true

    init(
        initialPosition: CGFloat = 0,
        maxSpeed: CGFloat = 180,
        acceleration: CGFloat = 360,
        deceleration: CGFloat = 480,
        arrivalThreshold: CGFloat = 4.0
    ) {
        self.currentPosition = initialPosition
        self.targetPosition = initialPosition
        self.maxSpeed = maxSpeed
        self.acceleration = acceleration
        self.deceleration = deceleration
        self.arrivalThreshold = arrivalThreshold
    }

    /// Sets a new target position. If the distance exceeds arrival threshold, marks active.
    func setTarget(_ target: CGFloat) {
        targetPosition = target
        if abs(targetPosition - currentPosition) > arrivalThreshold {
            isArrived = false
        }
    }

    /// Immediately teleports the interpolator to a specific position and halts velocity.
    func reset(to position: CGFloat) {
        currentPosition = position
        targetPosition = position
        currentVelocity = 0
        isArrived = true
    }

    /// Cancels active translation, holding the current position and zeroing velocity.
    func stop() {
        targetPosition = currentPosition
        currentVelocity = 0
        isArrived = true
    }

    /// Advances the interpolation by `dt` seconds using trapezoidal velocity profiling.
    ///
    /// - Parameter dt: Delta time in seconds elapsed since last update.
    /// - Returns: Tuple of updated `(position, velocity)`.
    @discardableResult
    func update(dt: TimeInterval) -> (position: CGFloat, velocity: CGFloat) {
        guard dt > 0 else { return (currentPosition, currentVelocity) }

        let delta = targetPosition - currentPosition
        let distance = abs(delta)

        // Arrived condition: within threshold and moving slowly
        if distance <= arrivalThreshold && abs(currentVelocity) <= (acceleration * CGFloat(dt) * 1.5) {
            currentPosition = targetPosition
            currentVelocity = 0
            isArrived = true
            return (currentPosition, 0)
        }

        let direction: CGFloat = delta > 0 ? 1.0 : -1.0

        // Physics braking formula: v^2 = 2 * a * d => stoppingDistance = v^2 / (2 * decel)
        let speed = abs(currentVelocity)
        let stoppingDistance = (speed * speed) / (2.0 * max(10, deceleration))

        if distance <= stoppingDistance {
            // Need to decelerate / brake
            let decelStep = deceleration * CGFloat(dt)
            if speed <= decelStep {
                currentVelocity = 0
            } else {
                currentVelocity -= (currentVelocity > 0 ? 1 : -1) * decelStep
            }
        } else {
            // Accelerate in target direction up to maxSpeed
            let targetVelocity = direction * maxSpeed
            let accelStep = acceleration * CGFloat(dt)
            if currentVelocity < targetVelocity {
                currentVelocity = min(targetVelocity, currentVelocity + accelStep)
            } else if currentVelocity > targetVelocity {
                currentVelocity = max(targetVelocity, currentVelocity - accelStep)
            }
        }

        currentPosition += currentVelocity * CGFloat(dt)
        return (currentPosition, currentVelocity)
    }
}
