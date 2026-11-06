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

    public void RecordLaunch(DateTime now)
    {
        FirstLaunchedAt ??= now;
        LastLaunchedAt = now;
        LaunchCount++;
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
