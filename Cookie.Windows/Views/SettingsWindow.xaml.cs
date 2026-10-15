using System;
using System.Windows;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Cookie.Windows.ViewModels;

namespace Cookie.Windows.Views;

public partial class SettingsWindow : Window
{
    public SettingsWindow(
        CookieProfile profile,
        SettingsManager settingsManager,
        AudioManagerBase audioManager,
        Action? onSettingsChanged = null)
    {
        InitializeComponent();
        DataContext = new SettingsViewModel(profile, settingsManager, audioManager, onSettingsChanged);
    }
}
