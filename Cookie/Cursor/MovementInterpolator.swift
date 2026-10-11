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

    /// Current interpolated position (1D X).
    private(set) var currentPosition: CGFloat

    /// Current signed velocity in points per second (1D X).
    private(set) var currentVelocity: CGFloat = 0

    /// Desired destination position (1D X).
    private(set) var targetPosition: CGFloat

    /// Indicates whether the position has arrived at the target within threshold.
    private(set) var isArrived: Bool = true

    /// Whether the interpolator is currently moving toward target.
    var isMoving: Bool {
        !isArrived
    }

    // MARK: - 2D Vector State

    /// Current interpolated 2D position in screen coordinates.
    private(set) var currentPosition2D: CGPoint = .zero

    /// Current 2D velocity vector in points per second.
    private(set) var currentVelocity2D: CGVector = .zero

    /// Desired 2D destination in screen coordinates.
    private(set) var targetPosition2D: CGPoint = .zero

    /// Indicates whether the 2D position has arrived at target within threshold.
    private(set) var isArrived2D: Bool = true

    /// Whether 2D motion is active.
    var isMoving2D: Bool {
        !isArrived2D
    }

    init(
        initialPosition: CGFloat = 0,
        maxSpeed: CGFloat = 180,
        acceleration: CGFloat = 360,
        deceleration: CGFloat = 480,
        arrivalThreshold: CGFloat = 4.0
    ) {
        self.currentPosition = initialPosition
        self.targetPosition = initialPosition
        self.currentPosition2D = CGPoint(x: initialPosition, y: 0)
        self.targetPosition2D = CGPoint(x: initialPosition, y: 0)
        self.maxSpeed = maxSpeed
        self.acceleration = acceleration
        self.deceleration = deceleration
        self.arrivalThreshold = arrivalThreshold
    }

    // MARK: - 1D Controls

    /// Sets a new target position. If the distance exceeds arrival threshold, marks active.
    func setTarget(_ target: CGFloat) {
        targetPosition = target
        targetPosition2D.x = target
        if abs(targetPosition - currentPosition) > arrivalThreshold {
            isArrived = false
            isArrived2D = false
        }
    }

    /// Immediately teleports the interpolator to a specific position and halts velocity.
    func reset(to position: CGFloat) {
        currentPosition = position
        targetPosition = position
        currentVelocity = 0
        isArrived = true

        currentPosition2D.x = position
        targetPosition2D.x = position
        currentVelocity2D.dx = 0
        isArrived2D = true
    }

    /// Alias for reset(to:) providing an intuitive snapping API.
    func snap(to position: CGFloat) {
        reset(to: position)
    }

    /// Cancels active translation, holding the current position and zeroing velocity.
    func stop() {
        targetPosition = currentPosition
        currentVelocity = 0
        isArrived = true

        targetPosition2D = currentPosition2D
        currentVelocity2D = .zero
        isArrived2D = true
    }

    // MARK: - 2D Vector Controls

    /// Sets a new 2D target position.
    func setTarget2D(_ target: CGPoint) {
        targetPosition2D = target
        targetPosition = target.x
        let dist = hypot(targetPosition2D.x - currentPosition2D.x, targetPosition2D.y - currentPosition2D.y)
        if dist > arrivalThreshold {
            isArrived2D = false
            isArrived = false
        }
    }

    /// Teleports 2D position immediately to a point and halts velocity.
    func reset2D(to position: CGPoint) {
        currentPosition2D = position
        targetPosition2D = position
        currentVelocity2D = .zero
        isArrived2D = true

        currentPosition = position.x
        targetPosition = position.x
        currentVelocity = 0
        isArrived = true
    }

    /// Snaps 2D position immediately to target point.
    func snap2D(to position: CGPoint) {
        reset2D(to: position)
    }

    /// Stops 2D motion immediately, zeroing velocity.
    func stop2D() {
        targetPosition2D = currentPosition2D
        currentVelocity2D = .zero
        isArrived2D = true

        targetPosition = currentPosition
        currentVelocity = 0
        isArrived = true
    }

    /// Advances the interpolation by `dt` seconds using trapezoidal velocity profiling.
    @discardableResult
    func update(deltaTime dt: TimeInterval) -> (position: CGFloat, velocity: CGFloat) {
        update(dt: dt)
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
        currentPosition2D.x = currentPosition
        return (currentPosition, currentVelocity)
    }

    /// Advances 2D vector interpolation by `dt` seconds using trapezoidal velocity profiling.
    ///
    /// - Parameter dt: Delta time in seconds elapsed since last update.
    /// - Returns: Tuple of updated `(position: CGPoint, velocity: CGVector)`.
    @discardableResult
    func update2D(dt: TimeInterval) -> (position: CGPoint, velocity: CGVector) {
        guard dt > 0 else { return (currentPosition2D, currentVelocity2D) }

        let dx = targetPosition2D.x - currentPosition2D.x
        let dy = targetPosition2D.y - currentPosition2D.y
        let distance = hypot(dx, dy)

        let currentSpeed = hypot(currentVelocity2D.dx, currentVelocity2D.dy)

        // Arrived condition: within threshold and moving slowly
        if distance <= arrivalThreshold && currentSpeed <= (acceleration * CGFloat(dt) * 1.5) {
            currentPosition2D = targetPosition2D
            currentVelocity2D = .zero
            isArrived2D = true
            currentPosition = currentPosition2D.x
            currentVelocity = 0
            isArrived = true
            return (currentPosition2D, .zero)
        }

        guard distance > 0.001 else {
            currentPosition2D = targetPosition2D
            currentVelocity2D = .zero
            isArrived2D = true
            currentPosition = currentPosition2D.x
            currentVelocity = 0
            isArrived = true
            return (currentPosition2D, .zero)
        }

        let dirX = dx / distance
        let dirY = dy / distance

        // Physics braking formula: v^2 = 2 * a * d => stoppingDistance = v^2 / (2 * decel)
        let stoppingDistance = (currentSpeed * currentSpeed) / (2.0 * max(10, deceleration))

        var newSpeed = currentSpeed
        if distance <= stoppingDistance {
            // Need to decelerate / brake
            let decelStep = deceleration * CGFloat(dt)
            newSpeed = max(0, currentSpeed - decelStep)
        } else {
            // Accelerate towards maxSpeed
            let accelStep = acceleration * CGFloat(dt)
            newSpeed = min(maxSpeed, currentSpeed + accelStep)
        }

        currentVelocity2D = CGVector(dx: dirX * newSpeed, dy: dirY * newSpeed)
        currentPosition2D = CGPoint(
            x: currentPosition2D.x + currentVelocity2D.dx * CGFloat(dt),
            y: currentPosition2D.y + currentVelocity2D.dy * CGFloat(dt)
        )

        currentPosition = currentPosition2D.x
        currentVelocity = currentVelocity2D.dx
        targetPosition = targetPosition2D.x
        isArrived = isArrived2D

        return (currentPosition2D, currentVelocity2D)
    }
}
