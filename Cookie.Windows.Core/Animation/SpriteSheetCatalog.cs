using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Animation;

/// <summary>A grid sprite sheet on disk and the order its cells play in.</summary>
public record SpriteSheet(string Name, string ImagePath, int Columns, int Rows, double Fps, IReadOnlyList<int> Frames);

/// <summary>One frame to draw: which sheet, which grid cell, and how to orient it.</summary>
public record SpriteFrameRef(SpriteSheet Sheet, int Cell, CookieDirection Direction, double HeadTilt);

/// <summary>
/// Finds sprite sheets laid out as Sprites/Cookie/&lt;Category&gt;/&lt;name&gt;.png with a
/// &lt;name&gt;.json manifest beside it, the same format the macOS app reads.
/// Sheets come from scripts/generate_sprites.py.
/// </summary>
public class SpriteSheetCatalog
{
    private const int MaxFrames = 64;

    /// <summary>Sheets painted from the base pose, the only ones accessories line up with.</summary>
    private static readonly HashSet<string> BasePoseSheets = new()
    {
        "idle", "idleBlink", "sit", "stretch", "yawn", "tired", "meow", "curious", "investigate", "jump", "pickedUp"
    };

    private readonly string[] _roots;
    private readonly Dictionary<(CookieAnimationCategory, string), SpriteSheet?> _cache = new();

    public SpriteSheetCatalog(params string[] roots)
    {
        _roots = roots;
    }

    public static bool IsDrawnFromBasePose(string sheetName) => BasePoseSheets.Contains(sheetName);

    public SpriteSheet? Find(CookieAnimationSpec spec)
    {
        var key = (spec.Category, spec.SheetName);
        if (!_cache.TryGetValue(key, out var sheet))
        {
            sheet = _roots
                .Select(root => Load(Path.Combine(root, spec.Category.ToString()), spec.SheetName))
                .FirstOrDefault(found => found != null);
            _cache[key] = sheet;
        }
        return sheet;
    }

    private static SpriteSheet? Load(string directory, string name)
    {
        string imagePath = Path.Combine(directory, name + ".png");
        string manifestPath = Path.Combine(directory, name + ".json");
        if (!File.Exists(imagePath) || !File.Exists(manifestPath)) return null;

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(manifestPath));
            var root = document.RootElement;

            var grid = root.GetProperty("grid");
            int columns = grid[0].GetInt32();
            int rows = grid[1].GetInt32();
            double fps = root.GetProperty("fps").GetDouble();
            if (columns <= 0 || rows <= 0 || fps <= 0) return null;

            int cellCount = Math.Min(columns * rows, MaxFrames);
            var frames = root.TryGetProperty("frames", out var order)
                ? order.EnumerateArray().Select(cell => cell.GetInt32()).Where(cell => cell >= 0 && cell < cellCount).ToList()
                : Enumerable.Range(0, cellCount).ToList();

            return frames.Count == 0 ? null : new SpriteSheet(name, imagePath, columns, rows, fps, frames);
        }
        catch (Exception exception) when (exception is JsonException or KeyNotFoundException or InvalidOperationException or IOException)
        {
            // A damaged manifest falls back to the vector cat instead of crashing.
            return null;
        }
    }
}
