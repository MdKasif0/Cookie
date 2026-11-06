import Foundation

/// What Cookie wears and says depending on the local date and time. Everything here
/// is computed from the system clock, so the app stays fully offline.
enum DailyRhythm {
    private static let headSlot: [AccessoryKind] = [.hat, .crown, .pumpkin, .santaHat]
    private static let neckSlot: [AccessoryKind] = [.collar, .bandana, .scarf]

    /// Accessories she wears today beyond what the user chose. Birthday, Halloween, the holidays
    /// and winter each have an outfit.
    static func outfit(on date: Date, firstMet: Date?, calendar: Calendar = .current) -> [AccessoryKind] {
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        var worn: [AccessoryKind] = []

        if isBirthday(on: date, firstMet: firstMet, calendar: calendar) {
            worn.append(.hat)
        } else if (month == 10 && day >= 24) || (month == 11 && day == 1) {
            worn.append(.pumpkin)
        } else if month == 12 && day >= 10 {
            worn.append(.santaHat)
        }

        if month == 12 || month == 1 || month == 2 {
            worn.append(.scarf)
        }
        return worn
    }

    /// The anniversary of the day you first met, once at least ten months have passed.
    static func isBirthday(on date: Date, firstMet: Date?, calendar: Calendar = .current) -> Bool {
        guard let firstMet else { return false }
        // Whole calendar days, so the hour you first met doesn't matter.
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: firstMet), to: calendar.startOfDay(for: date)).day ?? 0
        guard days >= 300 else { return false }
        let met = calendar.dateComponents([.month, .day], from: firstMet)
        let today = calendar.dateComponents([.month, .day], from: date)
        return met.month == today.month && met.day == today.day
    }

    /// Whole years together on a birthday.
    static func yearsTogether(on date: Date, firstMet: Date, calendar: Calendar = .current) -> Int {
        max(1, calendar.dateComponents([.year], from: calendar.startOfDay(for: firstMet), to: calendar.startOfDay(for: date)).year ?? 1)
    }

    /// What she says when she first appears, or nil for no greeting.
    static func greeting(name: String, on date: Date, firstMet: Date?, calendar: Calendar = .current) -> String {
        if isBirthday(on: date, firstMet: firstMet, calendar: calendar), let firstMet {
            let years = yearsTogether(on: date, firstMet: firstMet, calendar: calendar)
            return years == 1 ? "It's our birthday! One year together." : "It's our birthday! \(years) years together."
        }
        switch TimeOfDay.at(date, calendar: calendar) {
        case .morning: return "Good morning!"
        case .day: return "Hi there!"
        case .evening: return "Good evening!"
        case .lateNight: return "It's late. Sleepy time soon?"
        }
    }
}

extension CookieAppearanceConfig {
    /// This configuration plus the day's outfit. What the user picked always wins: an outfit
    /// piece is only added if nothing else already occupies its spot.
    func withDailyOutfit(on date: Date, firstMet: Date?, calendar: Calendar = .current) -> CookieAppearanceConfig {
        var result = self
        let hasHead = [AccessoryKind.hat, .crown, .pumpkin, .santaHat].contains { accessory(for: $0).isEnabled }
        let hasNeck = [AccessoryKind.collar, .bandana, .scarf].contains { accessory(for: $0).isEnabled }

        for kind in DailyRhythm.outfit(on: date, firstMet: firstMet, calendar: calendar) {
            let isHead = [AccessoryKind.hat, .crown, .pumpkin, .santaHat].contains(kind)
            if isHead ? hasHead : hasNeck { continue }
            var piece = result.accessory(for: kind)
            piece.isEnabled = true
            result.setAccessory(piece)
        }
        return result
    }
}
