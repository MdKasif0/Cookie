using System.Collections.Generic;

namespace Cookie.Windows.Models;

public static class CookiePoseCatalog
{
    private static readonly Dictionary<string, CookiePose[]> Poses = new()
    {
        ["idle"] = new[]
        {
            new CookiePose(tailAngle: -8),
            new CookiePose(squash: 1.02),
            new CookiePose(tailAngle: 8),
            new CookiePose(squash: 0.99)
        },
        ["idleBlink"] = new[]
        {
            new CookiePose(),
            new CookiePose(eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(),
            new CookiePose()
        },
        ["sit"] = new[]
        {
            new CookiePose(squash: 0.97, bodyY: -4),
            new CookiePose(squash: 0.98, bodyY: -3)
        },
        ["sleep"] = new[]
        {
            new CookiePose(squash: 0.96, bodyY: -4, headY: 2, headTilt: 6, tailAngle: 4, eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(squash: 0.94, bodyY: -5, headY: 3, headTilt: 6, tailAngle: -4, eyeStyle: CookieEyeStyle.Closed)
        },
        ["wake"] = new[]
        {
            new CookiePose(squash: 0.94, headTilt: -4, eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(bodyY: -2, headTilt: -8, eyeStyle: CookieEyeStyle.Half),
            new CookiePose(squash: 1.02)
        },
        ["stretch"] = new[]
        {
            new CookiePose(squash: 0.92, bodyY: -5, pawLift: 4, eyeStyle: CookieEyeStyle.Happy),
            new CookiePose(squash: 1.05, bodyY: 2, pawLift: 6, eyeStyle: CookieEyeStyle.Happy),
            new CookiePose(pawLift: 2, eyeStyle: CookieEyeStyle.Happy)
        },
        ["yawn"] = new[]
        {
            new CookiePose(eyeStyle: CookieEyeStyle.Half, mouthStyle: CookieMouthStyle.Open),
            new CookiePose(squash: 1.03, eyeStyle: CookieEyeStyle.Closed, mouthStyle: CookieMouthStyle.OpenWide),
            new CookiePose(eyeStyle: CookieEyeStyle.Half, mouthStyle: CookieMouthStyle.Open),
            new CookiePose()
        },
        ["groom"] = new[]
        {
            new CookiePose(headX: 5, headY: -7, headTilt: 12, eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(headX: 6, headY: -9, headTilt: 14, eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(headX: 5, headY: -7, headTilt: 12, eyeStyle: CookieEyeStyle.Closed)
        },
        ["walk"] = new[]
        {
            new CookiePose(bodyY: -1, tailAngle: 6, pawOffsetX: 3),
            new CookiePose(bodyY: 1),
            new CookiePose(bodyY: -1, tailAngle: -6, pawOffsetX: -3),
            new CookiePose(bodyY: 1)
        },
        ["run"] = new[]
        {
            new CookiePose(squash: 1.02, bodyY: -3, tailAngle: 12, pawOffsetX: 5),
            new CookiePose(bodyY: 2),
            new CookiePose(squash: 1.02, bodyY: -3, tailAngle: -12, pawOffsetX: -5),
            new CookiePose(bodyY: 2)
        },
        ["curious"] = new[]
        {
            new CookiePose(headTilt: 6, gazeX: 3),
            new CookiePose(headTilt: 6, tailAngle: 8, gazeX: -2)
        },
        ["happy"] = new[]
        {
            new CookiePose(squash: 0.92, bodyY: -4, eyeStyle: CookieEyeStyle.Happy),
            new CookiePose(squash: 1.08, bodyY: 6, eyeStyle: CookieEyeStyle.Happy),
            new CookiePose(squash: 0.98, eyeStyle: CookieEyeStyle.Happy)
        },
        ["surprised"] = new[]
        {
            new CookiePose(squash: 1.02, bodyY: 2, eyeStyle: CookieEyeStyle.Wide, mouthStyle: CookieMouthStyle.Open),
            new CookiePose(squash: 0.98, eyeStyle: CookieEyeStyle.Wide, mouthStyle: CookieMouthStyle.Open)
        },
        ["scared"] = new[]
        {
            new CookiePose(squash: 0.94, bodyY: -4, tailAngle: 20, earStyle: CookieEarStyle.Back, eyeStyle: CookieEyeStyle.Wide),
            new CookiePose(squash: 0.92, bodyY: -5, tailAngle: -20, earStyle: CookieEarStyle.Back, eyeStyle: CookieEyeStyle.Wide)
        },
        ["annoyed"] = new[]
        {
            new CookiePose(tailAngle: -6, eyeStyle: CookieEyeStyle.Half, mouthStyle: CookieMouthStyle.Flat),
            new CookiePose(tailAngle: 6, eyeStyle: CookieEyeStyle.Half, mouthStyle: CookieMouthStyle.Flat)
        },
        ["playful"] = new[]
        {
            new CookiePose(squash: 0.9, bodyY: -5, tailAngle: 18, eyeStyle: CookieEyeStyle.Wide),
            new CookiePose(squash: 0.94, bodyY: -3, tailAngle: -12, eyeStyle: CookieEyeStyle.Happy),
            new CookiePose(squash: 0.9, bodyY: -5, tailAngle: 14, eyeStyle: CookieEyeStyle.Wide)
        },
        ["eat"] = new[]
        {
            new CookiePose(headY: -6, mouthStyle: CookieMouthStyle.Open),
            new CookiePose(headY: -8, mouthStyle: CookieMouthStyle.Open),
            new CookiePose(headY: -6, mouthStyle: CookieMouthStyle.Open),
            new CookiePose(headY: -7, mouthStyle: CookieMouthStyle.OpenWide)
        },
        ["drink"] = new[]
        {
            new CookiePose(headY: -9, mouthStyle: CookieMouthStyle.Open),
            new CookiePose(headY: -11, mouthStyle: CookieMouthStyle.Open)
        },
        ["pet"] = new[]
        {
            new CookiePose(squash: 0.9, bodyY: -3, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.4),
            new CookiePose(squash: 1.06, bodyY: 5, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.5),
            new CookiePose(squash: 0.98, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.4)
        },
        ["meow"] = new[]
        {
            new CookiePose(headY: 3, eyeStyle: CookieEyeStyle.Half, mouthStyle: CookieMouthStyle.Open),
            new CookiePose(headY: 5, eyeStyle: CookieEyeStyle.Half, mouthStyle: CookieMouthStyle.OpenWide),
            new CookiePose(headY: 3, eyeStyle: CookieEyeStyle.Half, mouthStyle: CookieMouthStyle.Open)
        },
        ["jump"] = new[]
        {
            new CookiePose(squash: 0.88, bodyY: -4, eyeStyle: CookieEyeStyle.Happy),
            new CookiePose(squash: 1.1, bodyY: 12, pawLift: 4, eyeStyle: CookieEyeStyle.Happy),
            new CookiePose(squash: 1.02)
        },
        ["fall"] = new[]
        {
            new CookiePose(squash: 1.05, tailAngle: 25, pawLift: -4, earStyle: CookieEarStyle.Back, eyeStyle: CookieEyeStyle.Wide),
            new CookiePose(squash: 1.05, tailAngle: 15, pawLift: -4, earStyle: CookieEarStyle.Back, eyeStyle: CookieEyeStyle.Wide)
        },
        ["pickedUp"] = new[]
        {
            new CookiePose(squash: 1.03, tailAngle: 10, pawLift: -5, eyeStyle: CookieEyeStyle.Wide),
            new CookiePose(squash: 1.02, tailAngle: -6, pawLift: -4, eyeStyle: CookieEyeStyle.Wide)
        },
        ["dropped"] = new[]
        {
            new CookiePose(squash: 0.85, bodyY: -6, eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(squash: 0.92, bodyY: -2, eyeStyle: CookieEyeStyle.Wide),
            new CookiePose()
        },
        ["investigate"] = new[]
        {
            new CookiePose(squash: 0.95, headX: 4, headY: -4, headTilt: 4, tailAngle: -4, eyeStyle: CookieEyeStyle.Wide),
            new CookiePose(squash: 0.93, headX: 6, headY: -6, headTilt: 6, tailAngle: -8, eyeStyle: CookieEyeStyle.Open),
            new CookiePose(squash: 0.95, headX: 4, headY: -4, headTilt: 4, tailAngle: -4, eyeStyle: CookieEyeStyle.Wide)
        },
        ["tired"] = new[]
        {
            new CookiePose(squash: 0.94, bodyY: -3, headY: -2, tailAngle: 2, eyeStyle: CookieEyeStyle.Half, mouthStyle: CookieMouthStyle.Flat),
            new CookiePose(squash: 0.91, bodyY: -4, headY: -3, tailAngle: 0, eyeStyle: CookieEyeStyle.Happy, mouthStyle: CookieMouthStyle.Flat)
        },
        ["inBox"] = new[]
        {
            new CookiePose(squash: 0.88, bodyY: -10, headY: -6, eyeStyle: CookieEyeStyle.Open),
            new CookiePose(squash: 0.88, bodyY: -10, headY: -6, eyeStyle: CookieEyeStyle.Half)
        },
        ["boxPeek"] = new[]
        {
            new CookiePose(squash: 0.94, bodyY: -3, headY: 3, pawLift: 4, eyeStyle: CookieEyeStyle.Wide),
            new CookiePose(squash: 0.96, bodyY: -2, headY: 4, pawLift: 5, eyeStyle: CookieEyeStyle.Open)
        },
        ["wave"] = new[]
        {
            new CookiePose(headTilt: 2, eyeStyle: CookieEyeStyle.Wide),
            new CookiePose(headTilt: 3, pawLift: 3, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.3),
            new CookiePose(squash: 1.02, bodyY: 1, headTilt: 4, pawOffsetX: 3, pawLift: 6, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.4),
            new CookiePose(squash: 1.02, bodyY: 1, headTilt: 3, pawOffsetX: -2, pawLift: 7, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.4),
            new CookiePose(squash: 1.02, bodyY: 1, headTilt: 4, pawOffsetX: 3, pawLift: 6, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.4),
            new CookiePose(headTilt: 2, pawLift: 2, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.2),
            new CookiePose(eyeStyle: CookieEyeStyle.Happy),
            new CookiePose()
        },
        ["love"] = new[]
        {
            new CookiePose(headTilt: 2, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.2),
            new CookiePose(squash: 0.95, bodyY: -2, headTilt: 4, eyeStyle: CookieEyeStyle.Closed, blushScale: 1.5),
            new CookiePose(squash: 0.93, bodyY: -3, headTilt: 5, eyeStyle: CookieEyeStyle.Closed, blushScale: 1.7),
            new CookiePose(squash: 0.94, bodyY: -2, headTilt: 4, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.5),
            new CookiePose(squash: 0.97, headTilt: 2, eyeStyle: CookieEyeStyle.Happy, blushScale: 1.3),
            new CookiePose()
        },
        ["sleepy"] = new[]
        {
            new CookiePose(squash: 0.98, headY: -2, eyeStyle: CookieEyeStyle.Half),
            new CookiePose(squash: 1.02, headTilt: 2, eyeStyle: CookieEyeStyle.Half, mouthStyle: CookieMouthStyle.Open),
            new CookiePose(squash: 1.03, headTilt: 3, eyeStyle: CookieEyeStyle.Closed, mouthStyle: CookieMouthStyle.OpenWide),
            new CookiePose(squash: 0.95, bodyY: -3, headTilt: 4, eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(squash: 0.93, bodyY: -4, headTilt: 5, eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(squash: 0.94, bodyY: -3, headTilt: 5, eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(squash: 0.93, bodyY: -4, headTilt: 5, eyeStyle: CookieEyeStyle.Closed),
            new CookiePose(squash: 1.03, bodyY: 2, pawLift: 4, eyeStyle: CookieEyeStyle.Half),
            new CookiePose()
        }
    };

    public static CookiePose[]? GetFrames(string sheetName)
    {
        return Poses.TryGetValue(sheetName, out var frames) ? frames : null;
    }

    public static IReadOnlyCollection<string> RegisteredSheets => Poses.Keys;
}
