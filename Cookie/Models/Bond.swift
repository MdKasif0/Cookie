import Foundation

/// Something Cookie's friendship can unlock.
enum BondItem: Hashable, Identifiable {
    case accessory(AccessoryKind)
    case toy(ToyKind)
    case coat(FurPattern)
    case cozy(CozyKind)

    /// Stable identifier, also what is stored in the profile's unlock list.
    var id: String {
        switch self {
        case .accessory(let kind): return "accessory.\(kind.rawValue)"
        case .toy(let kind): return "toy.\(kind.rawValue)"
        case .coat(let pattern): return "coat.\(pattern.rawValue)"
        case .cozy(let kind): return "cozy.\(kind.rawValue)"
        }
    }

    var displayName: String {
        switch self {
        case .accessory(let kind): return kind.displayName
        case .toy(let kind): return kind.displayName
        case .coat(let pattern): return "\(pattern.displayName) Coat"
        case .cozy(let kind): return kind.displayName
        }
    }

    var categoryName: String {
        switch self {
        case .accessory: return "Accessory"
        case .toy: return "Toy"
        case .coat: return "Coat"
        case .cozy: return "Cozy spot"
        }
    }
}

struct BondLevel: Equatable, Identifiable {
    let index: Int
    let name: String
    /// Bond points needed to reach this level.
    let points: Int
    let unlocks: [BondItem]

    var id: Int { index }
}

struct BondProgress: Equatable {
    let level: BondLevel
    let next: BondLevel?
    /// 0...1 toward the next level; 1 at the top.
    let fraction: Double
    let pointsToNext: Int
}

/// Friendship with Cookie. It grows from affection (pets, treats, play, emotes, focus sessions)
/// and from the days you come back. All of it is local.
enum Bond {
    /// Each new day with Cookie is worth this many points, so returning matters
    /// as much as attention paid in one sitting.
    static let visitDayPoints = 5

    static let levels: [BondLevel] = [
        BondLevel(index: 0, name: "Just Met", points: 0, unlocks: []),
        BondLevel(index: 1, name: "Friends", points: 25, unlocks: [
            .toy(.feather), .accessory(.bow), .accessory(.collar)
        ]),
        BondLevel(index: 2, name: "Good Friends", points: 100, unlocks: [
            .toy(.toyMouse), .accessory(.bandana), .accessory(.glasses), .accessory(.pumpkin),
            .coat(.tabby), .cozy(.bed)
        ]),
        BondLevel(index: 3, name: "Best Friends", points: 250, unlocks: [
            .toy(.fishToy), .accessory(.hat), .accessory(.scarf), .accessory(.santaHat),
            .coat(.tuxedo), .cozy(.sunbeam)
        ]),
        BondLevel(index: 4, name: "Inseparable", points: 600, unlocks: [
            .accessory(.crown), .coat(.points), .cozy(.scratchingPost)
        ])
    ]

    static func points(for statistics: CookieStatistics) -> Int {
        statistics.affection + visitDayPoints * statistics.visitDays
    }

    static func level(forPoints points: Int) -> BondLevel {
        levels.last { points >= $0.points } ?? levels[0]
    }

    static func progress(forPoints points: Int) -> BondProgress {
        let current = level(forPoints: points)
        guard let next = levels.first(where: { $0.index == current.index + 1 }) else {
            return BondProgress(level: current, next: nil, fraction: 1, pointsToNext: 0)
        }
        let span = Double(next.points - current.points)
        let fraction = min(1, max(0, Double(points - current.points) / span))
        return BondProgress(level: current, next: next, fraction: fraction, pointsToNext: next.points - points)
    }

    /// The level that unlocks an item, or nil when it is there from the start.
    static func requiredLevel(for item: BondItem) -> BondLevel? {
        levels.first { $0.unlocks.contains(item) }
    }

    /// Items unlocked by reaching levels after `celebrated`, up to the level for `points`.
    static func newUnlocks(since celebrated: Int, points: Int) -> [BondItem] {
        let reached = level(forPoints: points).index
        guard reached > celebrated else { return [] }
        return levels.filter { $0.index > celebrated && $0.index <= reached }.flatMap(\.unlocks)
    }

    /// `extra` holds items kept available for other reasons, such as ones already in use
    /// before unlocks existed.
    static func isUnlocked(_ item: BondItem, points: Int, extra: Set<String> = []) -> Bool {
        guard let required = requiredLevel(for: item) else { return true }
        return points >= required.points || extra.contains(item.id)
    }
}

/// What happened when a friendship level was reached.
struct BondLevelUp: Equatable {
    let level: BondLevel
    let newItems: [BondItem]
}

extension CookieStore {
    var bondPoints: Int { Bond.points(for: statistics) }
    var bondProgress: BondProgress { Bond.progress(forPoints: bondPoints) }

    func isUnlocked(_ item: BondItem) -> Bool {
        Bond.isUnlocked(item, points: bondPoints, extra: Set(profile.unlockedAccessories))
    }

    /// Anything already in use stays available. Cookie's earlier versions had everything unlocked,
    /// so people who already wear a crown keep it.
    func keepInUseItemsUnlocked() {
        var inUse: [BondItem] = []
        for accessory in profile.customization.accessories where accessory.isEnabled {
            inUse.append(.accessory(accessory.kind))
        }
        inUse.append(.coat(profile.customization.furPattern))

        var kept = profile.unlockedAccessories
        for item in inUse where Bond.requiredLevel(for: item) != nil && !kept.contains(item.id) {
            kept.append(item.id)
        }
        if kept != profile.unlockedAccessories {
            profile.unlockedAccessories = kept
        }
    }

    /// Records a newly reached level, returning it once so it can be celebrated.
    func claimBondLevelUp() -> BondLevelUp? {
        let points = bondPoints
        let current = Bond.level(forPoints: points)
        guard current.index > statistics.celebratedBondLevel else { return nil }

        let items = Bond.newUnlocks(since: statistics.celebratedBondLevel, points: points)
        statistics.celebratedBondLevel = current.index

        var kept = profile.unlockedAccessories
        for item in items where !kept.contains(item.id) { kept.append(item.id) }
        if kept != profile.unlockedAccessories { profile.unlockedAccessories = kept }
        return BondLevelUp(level: current, newItems: items)
    }
}
