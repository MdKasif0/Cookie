using System;
using System.Windows;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Cookie.Windows.Core.Startup;
using Cookie.Windows.ViewModels;

namespace Cookie.Windows.Views;

public partial class SettingsWindow : Window
{
    private readonly CookieProfile _profile;

    public SettingsWindow(
        CookieProfile profile,
        SettingsManager settingsManager,
        AudioManagerBase audioManager,
        Action? onSettingsChanged = null,
        IStartupService? startupService = null,
        Action? onCheckForUpdates = null,
        SettingsHelperActions? helperActions = null)
    {
        InitializeComponent();
        Cookie.Windows.Desktop.CookieTheme.Attach(this);
        _profile = profile;

        var vm = new SettingsViewModel(
            profile,
            settingsManager,
            audioManager,
            () =>
            {
                UpdateLivePreview();
                onSettingsChanged?.Invoke();
            },
            startupService,
            onCheckForUpdates);

        DataContext = vm;

        HelpersTab.Content = new HelpersSettingsPanel(profile, settingsManager, onSettingsChanged, helperActions).Build();
        PowerToolsTab.Content = new PowerToolsSettingsPanel(profile, settingsManager, onSettingsChanged, helperActions).Build();
        Loaded += (s, e) => UpdateLivePreview();
    }

    /// <summary>Brings a tab to the front, for example Power Tools from the helpers tour.</summary>
    public void SelectTab(SettingsTab tab)
    {
        switch (tab)
        {
            case SettingsTab.Helpers: HelpersTab.IsSelected = true; break;
            case SettingsTab.PowerTools: PowerToolsTab.IsSelected = true; break;
        }
    }

    private void UpdateLivePreview()
    {
        PreviewCanvas?.UpdateAppearance(_profile.Appearance);
    }
}

/// <summary>Settings tabs that other parts of Cookie can open directly.</summary>
public enum SettingsTab { General, Helpers, PowerTools }
