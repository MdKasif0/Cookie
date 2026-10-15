using System;
using System.Windows;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;

namespace Cookie.Windows.Views;

public partial class OnboardingWindow : Window
{
    private readonly CookieProfile _profile;
    private readonly SettingsManager _settingsManager;
    private readonly Action? _onOpenSettings;

    public OnboardingWindow(
        CookieProfile profile,
        SettingsManager settingsManager,
        Action? onOpenSettings = null)
    {
        InitializeComponent();
        _profile = profile;
        _settingsManager = settingsManager;
        _onOpenSettings = onOpenSettings;

        OnboardingCanvas.UpdateAppearance(_profile.Appearance);
    }

    private void CustomizeBtn_Click(object sender, RoutedEventArgs e)
    {
        MarkOnboardingCompleted();
        Close();
        _onOpenSettings?.Invoke();
    }

    private void GetStartedBtn_Click(object sender, RoutedEventArgs e)
    {
        MarkOnboardingCompleted();
        Close();
    }

    private void MarkOnboardingCompleted()
    {
        _profile.Settings.HasCompletedOnboarding = true;
        _settingsManager.SaveProfileImmediate(_profile);
    }
}
