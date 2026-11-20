using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace Cookie.Windows.Core.Helpers;

// Pure models for the everyday helpers: the system watcher, sticky notes, the to-do list, and the
// downloads and screenshot helpers.

/// <summary>One look at the PC. Null means "couldn't tell", which never raises an alert.</summary>
public record SystemSnapshot(
    int? BatteryPercent = null,
    bool IsCharging = false,
    double? CpuLoad = null,
    long? DiskFreeBytes = null,
    long? DiskTotalBytes = null,
    bool? IsOnline = null);

public enum SystemAlertKind
{
    Battery,
    Cpu,
    Disk,
    Network
}

public static class SystemAlertKindExtensions
{
    public static string DisplayName(this SystemAlertKind kind) => kind switch
    {
        SystemAlertKind.Battery => "Low battery",
        SystemAlertKind.Cpu => "CPU maxed out for a few minutes",
        SystemAlertKind.Disk => "Disk almost full",
        _ => "Internet connection drops"
    };
}

public enum SystemAlertType
{
    LowBattery,
    CriticalBattery,
    CpuBusy,
    DiskAlmostFull,
    Offline,
    BackOnline
}

public record SystemAlert(SystemAlertType Type, int Value = 0)
{
    public SystemAlertKind Kind => Type switch
    {
        SystemAlertType.LowBattery or SystemAlertType.CriticalBattery => SystemAlertKind.Battery,
        SystemAlertType.CpuBusy => SystemAlertKind.Cpu,
        SystemAlertType.DiskAlmostFull => SystemAlertKind.Disk,
        _ => SystemAlertKind.Network
    };

    /// <summary>Important enough to come over a full-screen app.</summary>
    public bool IsUrgent => Type == SystemAlertType.CriticalBattery;

    public string Message => Type switch
    {
        SystemAlertType.LowBattery => $"Battery's at {Value}%. Time to find the charger?",
        SystemAlertType.CriticalBattery => $"Only {Value}% battery left! Plug in soon or save your work.",
        SystemAlertType.CpuBusy => "Your PC is working really hard. Something might be stuck.",
        SystemAlertType.DiskAlmostFull => $"Your disk is nearly full: only {Value} GB left.",
        SystemAlertType.Offline => "Uh oh, the internet just dropped.",
        _ => "We're back online!"
    };
}

/// <summary>Decides what is worth saying, with enough memory not to repeat itself.</summary>
public class SystemWatch
{
    public const int LowBattery = 20;
    public const int CriticalBattery = 10;
    /// <summary>Battery alerts re-arm once you charge past this.</summary>
    public const int BatteryRearm = 30;
    public const double BusyLoad = 0.9;
    /// <summary>Samples in a row above <see cref="BusyLoad"/> before she says anything.</summary>
    public const int BusySamples = 9;
    public static readonly TimeSpan CpuCooldown = TimeSpan.FromMinutes(30);
    public static readonly TimeSpan DiskCooldown = TimeSpan.FromHours(24);
    public const long LowDiskBytes = 10L * 1_000_000_000;
    public const double LowDiskFraction = 0.05;

    private bool _saidLow;
    private bool _saidCritical;
    private int _busyStreak;
    private DateTime _lastCpuAlert = DateTime.MinValue;
    private DateTime _lastDiskAlert = DateTime.MinValue;
    private bool? _wasOnline;
    private bool _saidOffline;

    /// <summary>Folds in a new snapshot and returns what to say, most important first.</summary>
    public List<SystemAlert> Update(SystemSnapshot snapshot, DateTime now, IReadOnlyCollection<SystemAlertKind> enabled)
    {
        var alerts = new List<SystemAlert>();

        if (snapshot.BatteryPercent is { } percent)
        {
            if (snapshot.IsCharging || percent >= BatteryRearm)
            {
                _saidLow = false;
                _saidCritical = false;
            }
            else if (percent <= CriticalBattery && !_saidCritical)
            {
                _saidCritical = true;
                _saidLow = true;
                if (enabled.Contains(SystemAlertKind.Battery)) alerts.Add(new SystemAlert(SystemAlertType.CriticalBattery, percent));
            }
            else if (percent <= LowBattery && !_saidLow)
            {
                _saidLow = true;
                if (enabled.Contains(SystemAlertKind.Battery)) alerts.Add(new SystemAlert(SystemAlertType.LowBattery, percent));
            }
        }

        if (snapshot.CpuLoad is { } load)
        {
            _busyStreak = load >= BusyLoad ? _busyStreak + 1 : 0;
            if (_busyStreak >= BusySamples && now - _lastCpuAlert >= CpuCooldown)
            {
                _lastCpuAlert = now;
                _busyStreak = 0;
                if (enabled.Contains(SystemAlertKind.Cpu)) alerts.Add(new SystemAlert(SystemAlertType.CpuBusy));
            }
        }

        if (snapshot.DiskFreeBytes is { } free && snapshot.DiskTotalBytes is { } total && total > 0)
        {
            bool low = free < LowDiskBytes || (double)free / total < LowDiskFraction;
            if (low && now - _lastDiskAlert >= DiskCooldown)
            {
                _lastDiskAlert = now;
                if (enabled.Contains(SystemAlertKind.Disk)) alerts.Add(new SystemAlert(SystemAlertType.DiskAlmostFull, (int)(free / 1_000_000_000)));
            }
        }

        if (snapshot.IsOnline is { } online)
        {
            if (_wasOnline == true && !online)
            {
                _saidOffline = enabled.Contains(SystemAlertKind.Network);
                if (_saidOffline) alerts.Add(new SystemAlert(SystemAlertType.Offline));
            }
            else if (_wasOnline == false && online && _saidOffline)
            {
                _saidOffline = false;
                alerts.Add(new SystemAlert(SystemAlertType.BackOnline));
            }
            _wasOnline = online;
        }

        return alerts.OrderByDescending(alert => alert.IsUrgent).ToList();
    }
}

/// <summary>CPU load from two readings of the system's idle, kernel and user times.</summary>
public static class CpuLoad
{
    public static double? Between((ulong Idle, ulong Kernel, ulong User) previous, (ulong Idle, ulong Kernel, ulong User) current)
    {
        ulong idle = current.Idle - previous.Idle;
        // Kernel time includes idle time.
        ulong total = (current.Kernel - previous.Kernel) + (current.User - previous.User);
        if (total == 0 || current.Idle < previous.Idle) return null;
        return Math.Clamp(1.0 - (double)idle / total, 0, 1);
    }
}

public enum StickyColor
{
    Yellow,
    Pink,
    Blue,
    Green
}

public static class StickyColorExtensions
{
    public static string Hex(this StickyColor color) => color switch
    {
        StickyColor.Pink => "#FFD3E2",
        StickyColor.Blue => "#CFE6FF",
        StickyColor.Green => "#D6F5CF",
        _ => "#FFF1A8"
    };

    public static StickyColor Next(this StickyColor color)
    {
        var all = Enum.GetValues<StickyColor>();
        return all[((int)color + 1) % all.Length];
    }
}

public class StickyNote
{
    public const int MaximumLength = 280;

    public Guid Id { get; set; } = Guid.NewGuid();
    public string Text { get; set; } = "";
    public StickyColor Color { get; set; } = StickyColor.Yellow;
    /// <summary>Top-left corner in screen DIPs; null until it has been placed.</summary>
    public double? Left { get; set; }
    public double? Top { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public const double Width = 180;
    public const double Height = 150;

    /// <summary>Where a new note goes: beside <paramref name="anchor"/> (Cookie or her bed), on screen.</summary>
    public static (double Left, double Top) PlaceBeside(Desktop.CoreRect anchor, Desktop.CoreRect workArea, int index)
    {
        double offset = index % 5 * 18;
        double x = anchor.Right + 12 + offset;
        if (x + Width > workArea.Right - 8) x = anchor.Left - Width - 12 - offset;
        x = Math.Clamp(x, workArea.Left + 8, Math.Max(workArea.Left + 8, workArea.Right - Width - 8));
        // Screen y grows downwards: sit just above the anchor's bottom edge.
        double y = Math.Clamp(anchor.Bottom - Height - 20 - offset, workArea.Top + 8, Math.Max(workArea.Top + 8, workArea.Bottom - Height - 8));
        return (x, y);
    }
}

public class TodoItem
{
    public const int MaximumCount = 12;

    public Guid Id { get; set; } = Guid.NewGuid();
    public string Text { get; set; } = "";
    public bool IsDone { get; set; }
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    public DateTime? DoneAt { get; set; }

    private static readonly string[] Cheers = { "Nice work!", "One down!", "{0} is proud of you!", "Look at you go!" };

    public static string Cheer(string name, Random? random = null)
        => string.Format(Cheers[(random ?? Random.Shared).Next(Cheers.Length)], name);
}

/// <summary>
/// Notices files that land in a folder and finish growing. Partial downloads are ignored until the browser
/// renames them, and nothing already there when watching starts is announced.
/// </summary>
public class DownloadWatch
{
    private static readonly HashSet<string> PartialExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".crdownload", ".download", ".part", ".partial", ".tmp", ".opdownload"
    };

    private HashSet<string> _known = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, long> _pending = new(StringComparer.OrdinalIgnoreCase);
    private bool _hasBaseline;

    public static bool IsPartial(string name)
        => name.StartsWith('.') || name.StartsWith("~$") || PartialExtensions.Contains(Path.GetExtension(name))
           || name.Equals("desktop.ini", StringComparison.OrdinalIgnoreCase);

    /// <summary><paramref name="listing"/> maps file names to sizes. Returns names that just finished.</summary>
    public List<string> Update(IReadOnlyDictionary<string, long> listing)
    {
        var names = new HashSet<string>(listing.Keys.Where(name => !IsPartial(name)), StringComparer.OrdinalIgnoreCase);
        if (!_hasBaseline)
        {
            _known = names;
            _hasBaseline = true;
            return new List<string>();
        }

        var finished = new List<string>();
        foreach (string name in names.Where(n => !_known.Contains(n)).OrderBy(n => n, StringComparer.OrdinalIgnoreCase))
        {
            long size = listing[name];
            if (_pending.TryGetValue(name, out long previous) && previous == size)
            {
                finished.Add(name);
                _pending.Remove(name);
                _known.Add(name);
            }
            else
            {
                _pending[name] = size;
            }
        }
        // Forget files that were moved away, so a new one with that name is noticed again.
        _known.IntersectWith(names);
        foreach (string gone in _pending.Keys.Where(n => !names.Contains(n)).ToList()) _pending.Remove(gone);
        return finished;
    }

    public static string Message(IReadOnlyList<string> names)
        => names.Count == 1 ? $"Your download finished: {names[0]}" : $"{names.Count} downloads finished!";
}

public static class ScreenshotTidy
{
    /// <summary>Screenshots older than this are offered for tidying.</summary>
    public static readonly TimeSpan MinimumAge = TimeSpan.FromHours(24);
    /// <summary>She brings it up when at least this many have piled up.</summary>
    public const int OfferThreshold = 8;

    private static readonly string[] Prefixes = { "screenshot", "screen shot", "screen recording", "screen capture", "snip", "capture" };
    private static readonly HashSet<string> Extensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png", ".jpg", ".jpeg", ".gif", ".bmp", ".mp4", ".webp"
    };

    public static bool IsScreenshot(string name)
    {
        string lower = name.ToLowerInvariant();
        return Extensions.Contains(Path.GetExtension(lower)) && Prefixes.Any(lower.StartsWith);
    }

    /// <summary>The screenshots old enough to move, by name.</summary>
    public static List<string> Candidates(IEnumerable<(string Name, DateTime ModifiedUtc)> files, DateTime nowUtc)
        => files.Where(f => IsScreenshot(f.Name) && nowUtc - f.ModifiedUtc >= MinimumAge)
                .Select(f => f.Name)
                .OrderBy(n => n, StringComparer.OrdinalIgnoreCase)
                .ToList();

    /// <summary>A name that doesn't collide with what is already there: "Shot.png", "Shot 2.png"…</summary>
    public static string UniqueName(string name, ISet<string> existing)
    {
        if (!existing.Contains(name)) return name;
        string stem = Path.GetFileNameWithoutExtension(name);
        string ext = Path.GetExtension(name);
        for (int index = 2; ; index++)
        {
            string candidate = $"{stem} {index}{ext}";
            if (!existing.Contains(candidate)) return candidate;
        }
    }

    public static string Offer(int count)
        => $"Your desktop has {count} old screenshots. Want me to tidy them? It's in my menu.";

    /// <summary>
    /// Moves the named files from <paramref name="folder"/> into <paramref name="destination"/>. Nothing is
    /// deleted or overwritten. Returns how many were moved.
    /// </summary>
    public static int Move(IEnumerable<string> names, string folder, string destination)
    {
        try
        {
            Directory.CreateDirectory(destination);
        }
        catch
        {
            return 0;
        }
        var existing = new HashSet<string>(Directory.EnumerateFileSystemEntries(destination).Select(Path.GetFileName)!, StringComparer.OrdinalIgnoreCase);
        int moved = 0;
        foreach (string name in names)
        {
            string target = UniqueName(name, existing);
            try
            {
                File.Move(Path.Combine(folder, name), Path.Combine(destination, target));
                existing.Add(target);
                moved++;
            }
            catch
            {
                // Skip what can't be moved.
            }
        }
        return moved;
    }
}
