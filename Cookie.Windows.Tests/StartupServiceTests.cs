using System;
using Cookie.Windows.Core.Startup;
using Xunit;

namespace Cookie.Windows.Tests;

public class StartupServiceTests
{
    [Fact]
    public void DefaultStartupService_DefaultsToDisabled()
    {
        var service = new DefaultStartupService();
        Assert.False(service.IsStartupEnabled());
    }

    [Fact]
    public void DefaultStartupService_CustomInitialState()
    {
        var service = new DefaultStartupService(initialEnabled: true);
        Assert.True(service.IsStartupEnabled());
    }

    [Fact]
    public void DefaultStartupService_ToggleStartupState()
    {
        var service = new DefaultStartupService();
        
        service.SetStartupEnabled(true);
        Assert.True(service.IsStartupEnabled());

        service.SetStartupEnabled(false);
        Assert.False(service.IsStartupEnabled());
    }

    [Fact]
    public void WindowsStartupService_CustomPathConstructor()
    {
        string customPath = @"C:\Users\TestUser\AppData\Local\Programs\Cookie\Cookie.exe";
        var service = new WindowsStartupService(customPath);

        Assert.Equal(customPath, service.GetApplicationPath());
    }

    [Fact]
    public void WindowsStartupService_DefaultConstructor_ResolvesExecutablePath()
    {
        var service = new WindowsStartupService();
        string path = service.GetApplicationPath();

        Assert.NotNull(path);
    }
}
