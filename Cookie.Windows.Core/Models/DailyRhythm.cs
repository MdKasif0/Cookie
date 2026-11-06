using System;
using System.Collections.Generic;
using System.Linq;

namespace Cookie.Windows.Core.Models;

/// <summary>Coarse local-time bucket used to shift behavior. Matches the macOS app's TimeOfDay.</summary>
public enum TimeOfDay
{
    /// <summary>05:00 to 10:00: wake up, stretch, gentle exploring.</summary>
    Morning,
    /// <summary>10:00 to 17:00: the baseline.</summary>
    Day,
    /// <summary>17:00 to 22:00: calmer, more sitting and grooming.</summary>
    Evening,
    /// <summary>22:00 to 05:00: sleepy, slow, long naps.</summary>
    LateNight
}

public static class TimeOfDayExtensions
{
    public static TimeOfDay At(DateTime local) => local.Hour switch
    {
        >= 5 and < 10 => TimeOfDay.Morning,
        >= 10 and < 17 => TimeOfDay.Day,
        >= 17 and < 22 => TimeOfDay.Evening,
        _ => TimeOfDay.LateNight
    };

    /// <summary>Chance that an idle moment turns into a nap.</summary>
    public static double NapChance(this TimeOfDay time) => time switch
    {
        TimeOfDay.LateNight => 0.15,
        TimeOfDay.Evening => 0.04,
        TimeOfDay.Day => 0.015,
        _ => 0.005
    };
}

/// <summary>
/// What Cookie wears and says depending on the local date and time. Everything here is computed from
/// the system clock, so the app stays fully offline. All dates are local.
/// </summary>
public static class DailyRhythm
{
    private static readonly AccessoryKind[] HeadSlot = { AccessoryKind.Hat, AccessoryKind.Crown, AccessoryKind.Pumpkin, AccessoryKind.SantaHat };
    private static readonly AccessoryKind[] NeckSlot = { AccessoryKind.Collar, AccessoryKind.Bandana, AccessoryKind.Scarf };

    /// <summary>Accessories she wears today beyond what the user chose: birthday, Halloween, the holidays and winter.</summary>
    public static IReadOnlyList<AccessoryKind> Outfit(DateTime date, DateTime? firstMet)
    {
        var worn = new List<AccessoryKind>();
        int month = date.Month;
        int day = date.Day;

        if (IsBirthday(date, firstMet)) worn.Add(AccessoryKind.Hat);
        else if ((month == 10 && day >= 24) || (month == 11 && day == 1)) worn.Add(AccessoryKind.Pumpkin);
        else if (month == 12 && day >= 10) worn.Add(AccessoryKind.SantaHat);

        if (month is 12 or 1 or 2) worn.Add(AccessoryKind.Scarf);
        return worn;
    }

    /// <summary>The anniversary of the day you first met, once at least ten months have passed.</summary>
    public static bool IsBirthday(DateTime date, DateTime? firstMet)
    {
        if (firstMet is not { } met) return false;
        // Whole calendar days, so the hour you first met doesn't matter.
        if ((date.Date - met.Date).Days < 300) return false;
        return met.Month == date.Month && met.Day == date.Day;
    }

    public static int YearsTogether(DateTime date, DateTime firstMet)
    {
        int years = date.Year - firstMet.Year;
        if (date.Date < firstMet.Date.AddYears(years)) years--;
        return Math.Max(1, years);
    }

    /// <summary>What she says when she first appears.</summary>
    public static string Greeting(DateTime date, DateTime? firstMet)
    {
        if (IsBirthday(date, firstMet) && firstMet is { } met)
        {
            int years = YearsTogether(date, met);
            return years == 1 ? "It's our birthday! One year together." : $"It's our birthday! {years} years together.";
        }
        return TimeOfDayExtensions.At(date) switch
        {
            TimeOfDay.Morning => "Good morning!",
            TimeOfDay.Day => "Hi there!",
            TimeOfDay.Evening => "Good evening!",
            _ => "It's late. Sleepy time soon?"
        };
    }

    /// <summary>
    /// This configuration plus the day's outfit. What the user picked always wins: an outfit piece is only
    /// added if nothing else already occupies its spot. The original is never changed.
    /// </summary>
    public static CookieAppearanceConfig WithDailyOutfit(this CookieAppearanceConfig config, DateTime date, DateTime? firstMet)
    {
        var result = config.Clone();
        bool hasHead = HeadSlot.Any(kind => config.Accessory(kind).IsEnabled);
        bool hasNeck = NeckSlot.Any(kind => config.Accessory(kind).IsEnabled);

        foreach (var kind in Outfit(date, firstMet))
        {
            bool isHead = HeadSlot.Contains(kind);
            if (isHead ? hasHead : hasNeck) continue;
            result.Accessory(kind).IsEnabled = true;
        }
        return result;
    }
}
