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

    init() {}

    mutating func recordLaunch(now: Date = Date()) {
        if firstLaunchedAt == nil { firstLaunchedAt = now }
        lastLaunchedAt = now
        launchCount += 1
    }

    private enum CodingKeys: String, CodingKey {
        case firstLaunchedAt, lastLaunchedAt, launchCount, petsReceived, affection
        case treatsGiven, toysPlayedWith, boxVisits
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
    }
}
