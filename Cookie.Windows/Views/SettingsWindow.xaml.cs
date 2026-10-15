using System;
using System.Windows;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Cookie.Windows.ViewModels;

namespace Cookie.Windows.Views;

public partial class SettingsWindow : Window
{
    private readonly CookieProfile _profile;

    public SettingsWindow(
        CookieProfile profile,
        SettingsManager settingsManager,
        AudioManagerBase audioManager,
        Action? onSettingsChanged = null)
    {
        InitializeComponent();
        _profile = profile;

        var vm = new SettingsViewModel(profile, settingsManager, audioManager, () =>
        {
            UpdateLivePreview();
            onSettingsChanged?.Invoke();
        });

        DataContext = vm;
        Loaded += (s, e) => UpdateLivePreview();
    }

    private void UpdateLivePreview()
    {
        PreviewCanvas?.UpdateAppearance(_profile.Appearance);
    }
}
