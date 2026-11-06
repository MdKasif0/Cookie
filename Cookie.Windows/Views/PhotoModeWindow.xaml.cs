using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Ellipse = System.Windows.Shapes.Ellipse;
using Shape = System.Windows.Shapes.Shape;
using System.Windows.Threading;
using Cookie.Windows.Core.Imaging;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Desktop;
using Cookie.Windows.Rendering;
using Microsoft.Win32;

namespace Cookie.Windows.Views;

/// <summary>Photo Mode: pick a pose and backdrop, then save Cookie as a PNG or an endlessly looping GIF, or copy her.</summary>
public partial class PhotoModeWindow : Window
{
    private readonly CookieProfile _profile;
    private readonly Func<CookieAppearanceConfig> _appearance;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromMilliseconds(30) };
    private readonly Dictionary<PhotoPose, ToggleButton> _poseButtons = new();
    private readonly Dictionary<PhotoBackdrop, Button> _backdropButtons = new();

    private PhotoPose _pose = PhotoPose.All[0];
    private PhotoBackdrop _backdrop = PhotoBackdrop.Transparent;
    private PhotoClip? _clip;
    private DateTime _started = DateTime.UtcNow;
    private bool _reduceMotion;

    public PhotoModeWindow(CookieProfile profile, Func<CookieAppearanceConfig> appearance)
    {
        InitializeComponent();
        CookieTheme.Attach(this);

        _profile = profile;
        _appearance = appearance;
        _reduceMotion = !SystemParameters.ClientAreaAnimation || profile.Settings.ReducedMotion == ReducedMotionMode.Always;

        BuildPoseButtons();
        BuildBackdropButtons();
        Reload();

        _timer.Tick += (s, e) => ShowFrame();
        Loaded += (s, e) => _timer.Start();
        Closed += (s, e) => _timer.Stop();
    }

    private void BuildPoseButtons()
    {
        foreach (var pose in PhotoPose.All)
        {
            var button = new ToggleButton { Content = pose.Title, Margin = new Thickness(0, 0, 6, 6), Padding = new Thickness(10, 5, 10, 5) };
            System.Windows.Automation.AutomationProperties.SetName(button, pose.Title);
            var captured = pose;
            button.Click += (s, e) =>
            {
                _pose = captured;
                Reload();
            };
            _poseButtons[pose] = button;
            PosePanel.Children.Add(button);
        }
    }

    private void BuildBackdropButtons()
    {
        foreach (var backdrop in Enum.GetValues<PhotoBackdrop>())
        {
            var swatch = new Ellipse { Width = 22, Height = 22, StrokeThickness = 1.5 };
            swatch.SetResourceReference(Shape.StrokeProperty, "BorderBeige");
            swatch.Fill = backdrop.GetColor() is { } color
                ? new SolidColorBrush(Color.FromRgb(color.R, color.G, color.B))
                : Brushes.Transparent;

            var button = new Button
            {
                Content = swatch,
                Margin = new Thickness(4, 0, 0, 0),
                Padding = new Thickness(4),
                ToolTip = backdrop.GetTitle()
            };
            System.Windows.Automation.AutomationProperties.SetName(button, $"{backdrop.GetTitle()} backdrop");
            var captured = backdrop;
            button.Click += (s, e) =>
            {
                _backdrop = captured;
                Reload();
            };
            _backdropButtons[backdrop] = button;
            BackdropPanel.Children.Add(button);
        }
    }

    private void Reload()
    {
        _clip = PhotoRenderer.Render(_pose, _appearance(), _backdrop);
        _started = DateTime.UtcNow;

        foreach (var (pose, button) in _poseButtons) button.IsChecked = pose == _pose;
        foreach (var (backdrop, button) in _backdropButtons)
        {
            button.BorderThickness = new Thickness(backdrop == _backdrop ? 2 : 1);
            button.SetResourceReference(Control.BorderBrushProperty, backdrop == _backdrop ? "AccentWarmOrange" : "BorderSubtle");
        }

        SaveGifButton.IsEnabled = _clip is { IsStill: false };
        GifNote.Visibility = _backdrop == PhotoBackdrop.Transparent && SaveGifButton.IsEnabled ? Visibility.Visible : Visibility.Collapsed;
        ShowFrame();
    }

    private void ShowFrame()
    {
        if (_clip == null)
        {
            PreviewImage.Source = null;
            return;
        }

        int index = _clip.IsStill || _reduceMotion
            ? 0
            : (int)((DateTime.UtcNow - _started).TotalSeconds * _clip.Fps) % _clip.Frames.Count;
        PreviewImage.Source = _clip.Frames[index];
    }

    private string SuggestedName(string extension) => $"{_profile.DisplayName}-{_pose.Id}.{extension}";

    private void SavePng_Click(object sender, RoutedEventArgs e)
    {
        if (_clip == null) return;
        var dialog = new SaveFileDialog { Filter = "PNG image (*.png)|*.png", FileName = SuggestedName("png"), InitialDirectory = PicturesFolder() };
        if (dialog.ShowDialog(this) != true) return;

        try
        {
            using var stream = File.Create(dialog.FileName);
            stream.Write(EncodePng(_clip.Frames[0]));
            StatusText.Text = $"Saved {Path.GetFileName(dialog.FileName)}.";
        }
        catch (IOException exception)
        {
            StatusText.Text = $"Couldn't save: {exception.Message}";
        }
    }

    private async void SaveGif_Click(object sender, RoutedEventArgs e)
    {
        if (_clip == null || _clip.IsStill) return;
        var dialog = new SaveFileDialog { Filter = "GIF animation (*.gif)|*.gif", FileName = SuggestedName("gif"), InitialDirectory = PicturesFolder() };
        if (dialog.ShowDialog(this) != true) return;

        var clip = _clip;
        var backdropColor = _backdrop.GetColor();
        StatusText.Text = "Making your GIF...";
        SaveGifButton.IsEnabled = false;
        try
        {
            // Dithering a whole animation takes a moment, so it happens off the UI thread. Frames are frozen, so this is safe.
            var bytes = await Task.Run(() =>
            {
                var frames = clip.Frames.Select(PhotoRenderer.ToRgba).ToList();
                int delay = Math.Max(2, (int)Math.Round(100.0 / Math.Max(clip.Fps, 1)));
                var matte = backdropColor ?? ((byte)250, (byte)238, (byte)225);
                return GifEncoder.Encode(frames, delay, loopForever: true, matte: matte);
            });
            await File.WriteAllBytesAsync(dialog.FileName, bytes);
            StatusText.Text = $"Saved {Path.GetFileName(dialog.FileName)}.";
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            StatusText.Text = $"Couldn't save: {exception.Message}";
        }
        finally
        {
            SaveGifButton.IsEnabled = true;
        }
    }

    private void Copy_Click(object sender, RoutedEventArgs e)
    {
        if (_clip == null) return;
        try
        {
            // Apps that understand "PNG" keep the transparency; the plain bitmap is the fallback.
            var data = new DataObject();
            data.SetData("PNG", new MemoryStream(EncodePng(_clip.Frames[0])));
            data.SetImage(_clip.Frames[0]);
            Clipboard.SetDataObject(data, true);
            StatusText.Text = "Copied to the clipboard.";
        }
        catch (System.Runtime.InteropServices.COMException)
        {
            StatusText.Text = "Another app is using the clipboard. Try again.";
        }
    }

    private static byte[] EncodePng(BitmapSource frame)
    {
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(frame));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    private static string PicturesFolder() => Environment.GetFolderPath(Environment.SpecialFolder.MyPictures);
}
