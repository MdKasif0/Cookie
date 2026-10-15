using System;
using System.Diagnostics;
using System.Windows;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Views;

public partial class AboutWindow : Window
{
    private readonly Action? _onCheckUpdates;

    public AboutWindow(CookieAppearanceConfig? appearance = null, Action? onCheckUpdates = null)
    {
        InitializeComponent();
        _onCheckUpdates = onCheckUpdates;

        if (appearance != null)
        {
            AboutCanvas.UpdateAppearance(appearance);
        }
    }

    private void CheckUpdatesBtn_Click(object sender, RoutedEventArgs e)
    {
        _onCheckUpdates?.Invoke();
    }

    private void WebsiteBtn_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "https://getcookie.app",
                UseShellExecute = true
            });
        }
        catch { }
    }

    private void CloseBtn_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
