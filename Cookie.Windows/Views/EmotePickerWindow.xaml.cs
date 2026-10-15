using System;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Interop;

namespace Cookie.Windows.Views;

public partial class EmotePickerWindow : Window
{
    private readonly CookieBehaviorController _behaviorController;
    private readonly Action? _onDismissed;
    private bool _isClosing = false;

    public EmotePickerWindow(CookieBehaviorController behaviorController, Action? onDismissed = null)
    {
        InitializeComponent();

        _behaviorController = behaviorController;
        _onDismissed = onDismissed;

        LoadThumbnails();
        UpdateCooldowns();

        Loaded += (s, e) =>
        {
            WaveBtn.Focus();
        };
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);

        var helper = new WindowInteropHelper(this);
        IntPtr hWnd = helper.Handle;

        int exStyle = NativeMethods.GetWindowLongPtr(hWnd, NativeMethods.GWL_EXSTYLE).ToInt32();
        exStyle |= NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE;
        NativeMethods.SetWindowLongPtr(hWnd, NativeMethods.GWL_EXSTYLE, new IntPtr(exStyle));
    }

    private void LoadThumbnails()
    {
        WaveImg.Source = LoadEmoteBitmap("Wave", "wave.png");
        HappyImg.Source = LoadEmoteBitmap("Happy", "happy.png");
        LoveImg.Source = LoadEmoteBitmap("Love", "love.png");
        SleepyImg.Source = LoadEmoteBitmap("Sleepy", "sleepy.png");
        PlayfulImg.Source = LoadEmoteBitmap("Playful", "playful.png");
    }

    private static BitmapImage? LoadEmoteBitmap(string folder, string fileName)
    {
        string path = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Resources", "Sprites", "Cookie", "Emotes", folder, fileName);
        if (File.Exists(path))
        {
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit();
                bmp.UriSource = new Uri(path, UriKind.Absolute);
                bmp.CacheOption = BitmapCacheOption.OnLoad;
                bmp.EndInit();
                bmp.Freeze();
                return bmp;
            }
            catch
            {
                return null;
            }
        }
        return null;
    }

    private void UpdateCooldowns()
    {
        WaveBtn.IsEnabled = _behaviorController.CanPerformEmote(Emote.Wave);
        HappyBtn.IsEnabled = _behaviorController.CanPerformEmote(Emote.Happy);
        LoveBtn.IsEnabled = _behaviorController.CanPerformEmote(Emote.Love);
        SleepyBtn.IsEnabled = _behaviorController.CanPerformEmote(Emote.Sleepy);
        PlayfulBtn.IsEnabled = _behaviorController.CanPerformEmote(Emote.Playful);

        if (_behaviorController.CurrentEmote != null)
        {
            StatusBadge.Text = "Emoting";
            StatusBadge.Foreground = (System.Windows.Media.Brush)FindResource("AccentWarmOrange");
        }
        else
        {
            StatusBadge.Text = "Ready";
            StatusBadge.Foreground = (System.Windows.Media.Brush)FindResource("MutedSage");
        }
    }

    private void TriggerAndDismiss(Emote emote)
    {
        if (_isClosing) return;

        bool triggered = _behaviorController.TriggerEmote(emote);
        if (!triggered) return;

        _isClosing = true;

        // Brief 140ms feedback delay like macOS before closing
        var timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(140)
        };
        timer.Tick += (s, e) =>
        {
            timer.Stop();
            ClosePicker();
        };
        timer.Start();
    }

    public void ClosePicker()
    {
        _onDismissed?.Invoke();
        Close();
    }

    private void OnCloseClick(object sender, RoutedEventArgs e) => ClosePicker();
    private void OnWaveClick(object sender, RoutedEventArgs e) => TriggerAndDismiss(Emote.Wave);
    private void OnHappyClick(object sender, RoutedEventArgs e) => TriggerAndDismiss(Emote.Happy);
    private void OnLoveClick(object sender, RoutedEventArgs e) => TriggerAndDismiss(Emote.Love);
    private void OnSleepyClick(object sender, RoutedEventArgs e) => TriggerAndDismiss(Emote.Sleepy);
    private void OnPlayfulClick(object sender, RoutedEventArgs e) => TriggerAndDismiss(Emote.Playful);

    private void OnWindowKeyDown(object sender, KeyEventArgs e)
    {
        switch (e.Key)
        {
            case Key.D1:
            case Key.NumPad1:
                TriggerAndDismiss(Emote.Wave);
                e.Handled = true;
                break;
            case Key.D2:
            case Key.NumPad2:
                TriggerAndDismiss(Emote.Happy);
                e.Handled = true;
                break;
            case Key.D3:
            case Key.NumPad3:
                TriggerAndDismiss(Emote.Love);
                e.Handled = true;
                break;
            case Key.D4:
            case Key.NumPad4:
                TriggerAndDismiss(Emote.Sleepy);
                e.Handled = true;
                break;
            case Key.D5:
            case Key.NumPad5:
                TriggerAndDismiss(Emote.Playful);
                e.Handled = true;
                break;

            case Key.Escape:
                ClosePicker();
                e.Handled = true;
                break;

            case Key.Left:
                NavigateLeft();
                e.Handled = true;
                break;
            case Key.Right:
                NavigateRight();
                e.Handled = true;
                break;
            case Key.Up:
                NavigateUp();
                e.Handled = true;
                break;
            case Key.Down:
                NavigateDown();
                e.Handled = true;
                break;
        }
    }

    private void NavigateLeft()
    {
        if (HappyBtn.IsFocused) WaveBtn.Focus();
        else if (LoveBtn.IsFocused) HappyBtn.Focus();
        else if (PlayfulBtn.IsFocused) SleepyBtn.Focus();
    }

    private void NavigateRight()
    {
        if (WaveBtn.IsFocused) HappyBtn.Focus();
        else if (HappyBtn.IsFocused) LoveBtn.Focus();
        else if (SleepyBtn.IsFocused) PlayfulBtn.Focus();
    }

    private void NavigateUp()
    {
        if (SleepyBtn.IsFocused) HappyBtn.Focus();
        else if (PlayfulBtn.IsFocused) LoveBtn.Focus();
    }

    private void NavigateDown()
    {
        if (WaveBtn.IsFocused) SleepyBtn.Focus();
        else if (HappyBtn.IsFocused) SleepyBtn.Focus();
        else if (LoveBtn.IsFocused) PlayfulBtn.Focus();
    }
}
