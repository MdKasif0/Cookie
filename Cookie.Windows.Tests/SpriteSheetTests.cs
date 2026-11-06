using System;
using System.IO;
using System.Linq;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Models;
using Xunit;

namespace Cookie.Windows.Tests;

public class SpriteSheetTests
{
    private static string RepoRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory != null && !File.Exists(Path.Combine(directory.FullName, "Cookie.Windows.sln")))
        {
            directory = directory.Parent;
        }
        return directory?.FullName ?? throw new DirectoryNotFoundException("Repository root not found.");
    }

    private static SpriteSheetCatalog ShippedCatalog() => new(
        Path.Combine(RepoRoot(), "Cookie", "Resources", "Sprites", "Cookie"),
        Path.Combine(RepoRoot(), "Cookie.Windows", "Resources", "Sprites", "Cookie"));

    public static TheoryData<CookieAnimationId> AllAnimations()
    {
        var data = new TheoryData<CookieAnimationId>();
        foreach (var id in Enum.GetValues<CookieAnimationId>()) data.Add(id);
        return data;
    }

    /// <summary>A gap here would make the cat flip between the 3D art and the vector drawing.</summary>
    [Theory]
    [MemberData(nameof(AllAnimations))]
    public void EveryAnimation_HasASheet(CookieAnimationId id)
    {
        Assert.NotNull(ShippedCatalog().Find(id.GetSpec()));
    }

    [Theory]
    [MemberData(nameof(AllAnimations))]
    public void SheetImage_MatchesItsManifestGrid(CookieAnimationId id)
    {
        var sheet = ShippedCatalog().Find(id.GetSpec())!;

        // PNG stores width and height as big-endian integers at bytes 16 and 20.
        var header = new byte[24];
        using (var stream = File.OpenRead(sheet.ImagePath)) stream.ReadExactly(header);
        int width = (header[16] << 24) | (header[17] << 16) | (header[18] << 8) | header[19];
        int height = (header[20] << 24) | (header[21] << 16) | (header[22] << 8) | header[23];

        Assert.Equal(360 * sheet.Columns, width);
        Assert.Equal(360 * sheet.Rows, height);
        Assert.All(sheet.Frames, cell => Assert.InRange(cell, 0, sheet.Columns * sheet.Rows - 1));
    }

    [Fact]
    public void EmptyGridCells_AreNeverPlayed()
    {
        // Ten frames fill a 6x2 grid, leaving two blank cells that would flicker.
        var walk = ShippedCatalog().Find(CookieAnimationId.WalkRight.GetSpec())!;

        Assert.Equal(12, walk.Columns * walk.Rows);
        Assert.Equal(Enumerable.Range(0, 10), walk.Frames);
    }

    [Fact]
    public void Controller_PlaysSheetFramesAtTheSheetsRate()
    {
        var controller = new CookieAnimationController(ShippedCatalog());
        SpriteFrameRef? latest = null;
        controller.OnSpriteFrameChanged += frame => latest = frame;

        controller.PlayAnimation(CookieAnimationId.WalkRight);
        Assert.Equal("walk", latest!.Sheet.Name);
        Assert.Equal(0, latest.Cell);

        controller.Update(1.01 / latest.Sheet.Fps);
        Assert.Equal(1, latest.Cell);
        Assert.Equal(CookieDirection.Right, latest.Direction);
    }

    [Fact]
    public void Controller_LoopsPastTheLastSheetFrame()
    {
        var controller = new CookieAnimationController(ShippedCatalog());
        SpriteFrameRef? latest = null;
        controller.OnSpriteFrameChanged += frame => latest = frame;
        controller.PlayAnimation(CookieAnimationId.WalkLeft);
        int frames = latest!.Sheet.Frames.Count;

        for (int i = 0; i < frames + 1; i++) controller.Update(1.01 / latest.Sheet.Fps);

        Assert.Equal(1, latest.Cell);
        Assert.Equal(CookieDirection.Left, latest.Direction);
    }

    [Fact]
    public void OneShotSheet_ReturnsToIdleAfterItsLastFrame()
    {
        var controller = new CookieAnimationController(ShippedCatalog());
        CookieAnimationId? completed = null;
        controller.OnAnimationCompleted += id => completed = id;
        controller.PlayAnimation(CookieAnimationId.Stretch);
        var sheet = ShippedCatalog().Find(CookieAnimationId.Stretch.GetSpec())!;

        for (int i = 0; i < sheet.Frames.Count; i++) controller.Update(1.01 / sheet.Fps);

        Assert.Equal(CookieAnimationId.Stretch, completed);
        Assert.Equal(CookieAnimationId.Idle, controller.CurrentAnimationId);
    }

    [Fact]
    public void Controller_WithoutSheets_StillPlaysPoses()
    {
        var controller = new CookieAnimationController(new SpriteSheetCatalog(Path.GetTempPath()));
        bool spriteFrameSent = false;
        CookiePose? pose = null;
        controller.OnSpriteFrameChanged += _ => spriteFrameSent = true;
        controller.OnFrameChanged += (p, _) => pose = p;

        controller.PlayAnimation(CookieAnimationId.WalkRight);

        Assert.False(spriteFrameSent);
        Assert.NotNull(pose);
    }

    [Theory]
    [InlineData("not json")]
    [InlineData("{\"grid\":[0,1],\"fps\":8}")]
    [InlineData("{\"fps\":8}")]
    [InlineData("{\"grid\":[2,1],\"fps\":8,\"frames\":[9]}")]
    public void DamagedManifest_IsIgnored(string manifest)
    {
        string root = Path.Combine(Path.GetTempPath(), $"cookie-sprites-{Guid.NewGuid():N}");
        string folder = Path.Combine(root, "Idle");
        Directory.CreateDirectory(folder);
        try
        {
            File.WriteAllBytes(Path.Combine(folder, "idle.png"), new byte[] { 0 });
            File.WriteAllText(Path.Combine(folder, "idle.json"), manifest);

            Assert.Null(new SpriteSheetCatalog(root).Find(CookieAnimationId.Idle.GetSpec()));
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    [Theory]
    [InlineData(FurPattern.Tabby, EyeColor.Charcoal, true)]
    [InlineData(FurPattern.None, EyeColor.Honey, true)]
    [InlineData(FurPattern.None, EyeColor.Charcoal, false)]
    public void CustomCoatsAndEyes_UseTheVectorRenderer(FurPattern pattern, EyeColor eyes, bool expected)
    {
        var appearance = new CookieAppearanceConfig { Pattern = pattern, EyeColor = eyes };

        Assert.Equal(expected, appearance.RequiresVectorRenderer);
    }

    [Fact]
    public void EveryFurColor_ExceptWarmWhite_HasATint()
    {
        var untinted = Enum.GetValues<FurColor>().Where(color => color.GetPaintedArtTint() == null);

        Assert.Equal(new[] { FurColor.WarmWhite }, untinted);
    }
}
