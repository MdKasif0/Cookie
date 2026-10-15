using System;
using Cookie.Windows.Core.Context;
using Cookie.Windows.Core.Desktop;
using Xunit;

namespace Cookie.Windows.Tests;

public class ApplicationContextTests
{
    [Theory]
    [InlineData("devenv", "Microsoft Visual Studio", ApplicationCategory.CodeEditor)]
    [InlineData("Code", "file.cs - Visual Studio Code", ApplicationCategory.CodeEditor)]
    [InlineData("cursor", "index.ts - Cursor", ApplicationCategory.CodeEditor)]
    [InlineData("notepad", "Untitled - Notepad", ApplicationCategory.CodeEditor)]
    [InlineData("rider64", "Cookie.sln - JetBrains Rider", ApplicationCategory.CodeEditor)]
    [InlineData("chrome", "New Tab - Google Chrome", ApplicationCategory.Browser)]
    [InlineData("msedge", "Microsoft Edge", ApplicationCategory.Browser)]
    [InlineData("firefox", "Mozilla Firefox", ApplicationCategory.Browser)]
    [InlineData("brave", "Brave", ApplicationCategory.Browser)]
    [InlineData("photoshop", "Adobe Photoshop 2026", ApplicationCategory.Creative)]
    [InlineData("blender", "Blender 4.2", ApplicationCategory.Creative)]
    [InlineData("figma", "Design System - Figma", ApplicationCategory.Creative)]
    [InlineData("illustrator", "Adobe Illustrator", ApplicationCategory.Creative)]
    [InlineData("slack", "Slack | General", ApplicationCategory.Communication)]
    [InlineData("discord", "Discord", ApplicationCategory.Communication)]
    [InlineData("teams", "Microsoft Teams", ApplicationCategory.Communication)]
    [InlineData("explorer", "Downloads", ApplicationCategory.FileManager)]
    public void Classify_KnownProcesses_MapsToExpectedBroadCategories(string procName, string windowTitle, ApplicationCategory expected)
    {
        var category = ApplicationCategoryExtensions.Classify(procName, windowTitle);
        Assert.Equal(expected, category);
    }

    [Theory]
    [InlineData("randomproc123", "Some Window")]
    [InlineData("mysteryapp", "")]
    [InlineData(null, null)]
    public void Classify_UnknownOrUncertainProcess_SafelyReturnsUnknownOrOther(string? procName, string? windowTitle)
    {
        var category = ApplicationCategoryExtensions.Classify(procName, windowTitle);
        Assert.True(category is ApplicationCategory.Unknown or ApplicationCategory.Other);
    }

    [Fact]
    public void PrivacyBoundary_ApplicationContextStoresOnlyMinimalMetadata()
    {
        var now = DateTime.UtcNow;
        var rect = new CoreRect(100, 100, 800, 600);
        var context = new ApplicationContext(
            DesktopContextState.AnotherAppActive,
            "code",
            "CookieBehaviorController.cs",
            1234,
            ApplicationCategory.CodeEditor,
            false,
            rect,
            now);

        // Verify that only broad public metadata is retained
        Assert.Equal(DesktopContextState.AnotherAppActive, context.State);
        Assert.Equal("code", context.ProcessName);
        Assert.Equal(1234, context.ProcessId);
        Assert.Equal(ApplicationCategory.CodeEditor, context.Category);
        Assert.False(context.IsCookieActive);
        Assert.Equal(rect, context.FrontmostWindowBounds);
        Assert.Equal(now, context.Timestamp);
    }

    [Fact]
    public void DefaultApplicationContextDetector_TracksContextSwitchesAndFiresEvents()
    {
        DateTime clock = new DateTime(2026, 10, 15, 14, 0, 0, DateTimeKind.Utc);
        var detector = new DefaultApplicationContextDetector
        {
            Now = () => clock
        };

        ApplicationContext? switchedContext = null;
        detector.OnApplicationSwitched += ctx => switchedContext = ctx;

        Assert.Equal(ApplicationContext.Unknown, detector.CurrentContext);
        Assert.Null(detector.PreviousContext);

        // Switch to code editor
        var editorContext = new ApplicationContext(
            DesktopContextState.AnotherAppActive,
            "devenv",
            "Cookie.sln - Visual Studio",
            4321,
            ApplicationCategory.CodeEditor,
            false,
            new CoreRect(50, 50, 1200, 800),
            clock);

        detector.SimulateSwitch(editorContext);

        Assert.Equal(editorContext, detector.CurrentContext);
        Assert.Equal(ApplicationContext.Unknown, detector.PreviousContext);
        Assert.NotNull(switchedContext);
        Assert.Equal("devenv", switchedContext.ProcessName);

        // Switch to desktop visible
        clock = clock.AddSeconds(10);
        var desktopContext = new ApplicationContext(
            DesktopContextState.DesktopVisible,
            "explorer",
            "Program Manager",
            100,
            ApplicationCategory.FileManager,
            false,
            null,
            clock);

        detector.SimulateSwitch(desktopContext);

        Assert.Equal(desktopContext, detector.CurrentContext);
        Assert.Equal(editorContext, detector.PreviousContext);
    }
}
