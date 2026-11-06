import Foundation

/// Lightweight local usage statistics shown on the Statistics settings tab.
struct CookieStatistics: Codable, Equatable {
    var firstLaunchedAt: Date?
    var lastLaunchedAt: Date?
    var launchCount: Int = 0
    var petsReceived: Int = 0
    var affection: Int = 0
    var treatsGiven: Int = 0
    var toysPlayedWith: Int = 0
    var boxVisits: Int = 0
    var toyPlayCounts: [String: Int] = [:]
    /// Distinct calendar days Cookie has been around. Each one adds to the bond.
    var visitDays: Int = 0
    var lastVisitedAt: Date?
    var focusSessions: Int = 0
    var focusMinutes: Int = 0
    /// The highest friendship level already celebrated, so each is announced once.
    var celebratedBondLevel: Int = 0

    init() {}

    mutating func recordLaunch(now: Date = Date()) {
        if firstLaunchedAt == nil { firstLaunchedAt = now }
        lastLaunchedAt = now
        launchCount += 1
        recordVisit(now: now)
    }

    /// Counts today as a visit, once. Returns whether it was new.
    @discardableResult
    mutating func recordVisit(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let last = lastVisitedAt, calendar.isDate(last, inSameDayAs: now) { return false }
        lastVisitedAt = now
        visitDays += 1
        return true
    }

    mutating func recordFocusSession(minutes: Int) {
        focusSessions += 1
        focusMinutes += minutes
        affection += 5
    }

    mutating func recordToyPlayed(_ toy: ToyKind) {
        toysPlayedWith += 1
        toyPlayCounts[toy.rawValue, default: 0] += 1
    }

    /// The toy Cookie has played with the most, if any.
    var favoriteToy: ToyKind? {
        guard let maxEntry = toyPlayCounts.max(by: { $0.value < $1.value }), maxEntry.value > 0 else {
            return nil
        }
        return ToyKind(rawValue: maxEntry.key)
    }

    /// Total sum of direct interactions across petting, feeding, and play.
    var totalInteractions: Int {
        petsReceived + treatsGiven + toysPlayedWith + boxVisits
    }

    private enum CodingKeys: String, CodingKey {
        case firstLaunchedAt, lastLaunchedAt, launchCount, petsReceived, affection
        case treatsGiven, toysPlayedWith, boxVisits, toyPlayCounts
        case visitDays, lastVisitedAt, focusSessions, focusMinutes, celebratedBondLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        firstLaunchedAt = try container.decodeIfPresent(Date.self, forKey: .firstLaunchedAt)
        lastLaunchedAt = try container.decodeIfPresent(Date.self, forKey: .lastLaunchedAt)
        launchCount = try container.decodeIfPresent(Int.self, forKey: .launchCount) ?? 0
        petsReceived = try container.decodeIfPresent(Int.self, forKey: .petsReceived) ?? 0
        affection = try container.decodeIfPresent(Int.self, forKey: .affection) ?? 0
        treatsGiven = try container.decodeIfPresent(Int.self, forKey: .treatsGiven) ?? 0
        toysPlayedWith = try container.decodeIfPresent(Int.self, forKey: .toysPlayedWith) ?? 0
        boxVisits = try container.decodeIfPresent(Int.self, forKey: .boxVisits) ?? 0
        toyPlayCounts = try container.decodeIfPresent([String: Int].self, forKey: .toyPlayCounts) ?? [:]
        visitDays = try container.decodeIfPresent(Int.self, forKey: .visitDays) ?? 0
        lastVisitedAt = try container.decodeIfPresent(Date.self, forKey: .lastVisitedAt)
        focusSessions = try container.decodeIfPresent(Int.self, forKey: .focusSessions) ?? 0
        focusMinutes = try container.decodeIfPresent(Int.self, forKey: .focusMinutes) ?? 0
        celebratedBondLevel = try container.decodeIfPresent(Int.self, forKey: .celebratedBondLevel) ?? 0
    }
}
