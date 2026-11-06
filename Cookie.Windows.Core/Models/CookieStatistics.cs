using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json.Serialization;

namespace Cookie.Windows.Core.Models;

/// <summary>Local usage statistics shown on the Stats settings tab. Never leaves the device.</summary>
public class CookieStatistics
{
    public DateTime? FirstLaunchedAt { get; set; }
    public DateTime? LastLaunchedAt { get; set; }
    public int LaunchCount { get; set; }
    public int PetsReceived { get; set; }
    public int Affection { get; set; }
    public int TreatsGiven { get; set; }
    public int ToysPlayedWith { get; set; }
    public int BoxVisits { get; set; }
    public Dictionary<ToyKind, int> ToyPlayCounts { get; set; } = new();

    /// <summary>Distinct calendar days Cookie has been around. Each one adds to the bond.</summary>
    public int VisitDays { get; set; }
    public DateTime? LastVisitedAt { get; set; }
    public int FocusSessions { get; set; }
    public int FocusMinutes { get; set; }

    /// <summary>The highest friendship level already celebrated, so each is announced once.</summary>
    public int CelebratedBondLevel { get; set; }

    public void RecordLaunch(DateTime now)
    {
        FirstLaunchedAt ??= now;
        LastLaunchedAt = now;
        LaunchCount++;
        RecordVisit(now);
    }

    /// <summary>Counts today as a visit, once. Returns whether it was new.</summary>
    public bool RecordVisit(DateTime now, TimeZoneInfo? zone = null)
    {
        zone ??= TimeZoneInfo.Local;
        if (LastVisitedAt is { } last && TimeZoneInfo.ConvertTime(last, zone).Date == TimeZoneInfo.ConvertTime(now, zone).Date)
        {
            return false;
        }
        LastVisitedAt = now;
        VisitDays++;
        return true;
    }

    public void RecordFocusSession(int minutes)
    {
        FocusSessions++;
        FocusMinutes += minutes;
        Affection += 5;
    }

    public void RecordPet()
    {
        PetsReceived++;
        Affection++;
    }

    public void RecordToyPlayed(ToyKind toy)
    {
        ToysPlayedWith++;
        ToyPlayCounts[toy] = ToyPlayCounts.GetValueOrDefault(toy) + 1;
    }

    [JsonIgnore]
    public ToyKind? FavoriteToy
    {
        get
        {
            if (ToyPlayCounts.Count == 0) return null;
            var top = ToyPlayCounts.MaxBy(entry => entry.Value);
            return top.Value > 0 ? top.Key : null;
        }
    }

    [JsonIgnore]
    public string FavoriteToyDisplay => FavoriteToy is { } toy ? $"{toy.GetDisplayName()} {toy.GetEmoji()}" : "None yet";

    [JsonIgnore]
    public int TotalInteractions => PetsReceived + TreatsGiven + ToysPlayedWith + BoxVisits;

    [JsonIgnore]
    public string FirstMetDisplay => FirstLaunchedAt?.ToLocalTime().ToString("D") ?? "Today";

    public int DaysTogether(DateTime now)
    {
        if (!FirstLaunchedAt.HasValue) return 1;
        return Math.Max(1, (now.Date - FirstLaunchedAt.Value.Date).Days + 1);
    }

    [JsonIgnore]
    public int DaysTogetherToday => DaysTogether(DateTime.UtcNow);
}
