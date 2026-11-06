using System;
using System.Collections.Generic;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Cookie.Windows.Core.Animation;
using Cookie.Windows.Core.Audio;
using Cookie.Windows.Core.Behaviors;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Core.Persistence;
using Cookie.Windows.Desktop;
using Cookie.Windows.Rendering;

namespace Cookie.Windows.Views;

/// <summary>First-run setup: Cookie walks in, reacts as you name her, and each personality has a living card.</summary>
public partial class OnboardingWindow : Window
{
    private const double FrameInterval = 1.0 / 30.0;
    private const double RestingX = 96;
    private const double OffstageX = -210;

    private readonly CookieProfile _profile;
    private readonly SettingsManager _settingsManager;
    private readonly Action<bool>? _onFinished;
    private readonly OnboardingDirector _director;
    private readonly bool _reduceMotion;
    private readonly DispatcherTimer _timer;
    private readonly Dictionary<CookiePersonality, PersonalityCard> _cards = new();

    private DateTime _lastTick = DateTime.UtcNow;
    private bool _arrivalShown;
    private bool _finished;

    public OnboardingWindow(
        CookieProfile profile,
        SettingsManager settingsManager,
        AudioManagerBase? audioManager = null,
        Action<bool>? onFinished = null)
    {
        InitializeComponent();
        CookieTheme.Attach(this);

        _profile = profile;
        _settingsManager = settingsManager;
        _onFinished = onFinished;
        _reduceMotion = !SystemParameters.ClientAreaAnimation
            || profile.Settings.ReducedMotion == ReducedMotionMode.Always;

        StageCat.UpdateAppearance(profile.Appearance);

        var stageAnimation = new CookieAnimationController(SpriteFrameCache.Catalog);
        stageAnimation.OnSpriteFrameChanged += StageCat.UpdateSpriteFrame;
        stageAnimation.OnFrameChanged += StageCat.UpdatePose;
        _director = new OnboardingDirector(stageAnimation, audioManager, profile.DisplayName, profile.Personality, _reduceMotion);

        NameBox.Text = profile.DisplayName;
        BuildCards();
        ShowPersonality(profile.Personality);
        UpdateName();
        PlaceCat();

        _timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromSeconds(FrameInterval) };
        _timer.Tick += OnTick;
        Loaded += (s, e) =>
        {
            _lastTick = DateTime.UtcNow;
            _timer.Start();
            NameBox.Focus();
            NameBox.SelectAll();
        };
        Closed += OnWindowClosed;
    }

    private void BuildCards()
    {
        foreach (var personality in Enum.GetValues<CookiePersonality>())
        {
            var card = new PersonalityCard(personality, _profile.Appearance, _reduceMotion);
            var captured = personality;
            card.Button.Click += (s, e) =>
            {
                _director.Personality = captured;
                ShowPersonality(captured);
            };
            _cards[personality] = card;
            PersonalityGrid.Children.Add(card.Button);
        }
    }

    private void ShowPersonality(CookiePersonality selected)
    {
        foreach (var (personality, card) in _cards)
        {
            card.SetSelected(personality == selected);
        }
        SummaryText.Text = selected.GetSummary();
    }

    private void UpdateName()
    {
        SpeechText.Text = _director.Greeting;
        GetStartedBtn.Content = $"Bring {_director.ResolvedName} Home";
    }

    private void NameBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_director == null) return;
        _director.Name = NameBox.Text;
        UpdateName();
    }

    private void OnTick(object? sender, EventArgs e)
    {
        var now = DateTime.UtcNow;
        double elapsed = Math.Min((now - _lastTick).TotalSeconds, 0.1);
        _lastTick = now;

        _director.Update(elapsed);
        PlaceCat();

        if (_director.HasArrived && !_arrivalShown)
        {
            _arrivalShown = true;
            ShowArrival();
        }

        if (!_reduceMotion)
        {
            foreach (var card in _cards.Values) card.Update(elapsed);
        }
    }

    private void PlaceCat()
    {
        Canvas.SetLeft(StageCat, RestingX + (OffstageX - RestingX) * _director.WalkRemaining);
    }

    private void ShowArrival()
    {
        var duration = TimeSpan.FromMilliseconds(_reduceMotion ? 0 : 260);
        SpeechBubble.BeginAnimation(OpacityProperty, new DoubleAnimation(1, duration));
        FloorShadow.BeginAnimation(OpacityProperty, new DoubleAnimation(1, duration));
    }

    private void CustomizeBtn_Click(object sender, RoutedEventArgs e) => Finish(openCustomization: true);

    private void GetStartedBtn_Click(object sender, RoutedEventArgs e) => Finish(openCustomization: false);

    private void Finish(bool openCustomization)
    {
        if (_finished) return;
        _finished = true;
        Save();
        Close();
        _onFinished?.Invoke(openCustomization);
    }

    private void Save()
    {
        _profile.DisplayName = _director.ResolvedName;
        _profile.Personality = _director.Personality;
        _profile.Settings.HasCompletedOnboarding = true;
        _settingsManager.SaveProfileImmediate(_profile);
    }

    /// <summary>Closing the window still brings Cookie out, with whatever was chosen so far.</summary>
    private void OnWindowClosed(object? sender, EventArgs e)
    {
        _timer.Stop();
        if (_finished) return;
        _finished = true;
        Save();
        _onFinished?.Invoke(false);
    }

    /// <summary>A button showing one personality as a small looping animation.</summary>
    private sealed class PersonalityCard
    {
        private readonly CookieAnimationController _animation;
        private readonly CookieAnimationId _showcase;
        private readonly Border _surface;

        public Button Button { get; }

        public PersonalityCard(CookiePersonality personality, CookieAppearanceConfig appearance, bool reduceMotion)
        {
            var canvas = new CookieCanvas { Width = 76, Height = 76, HorizontalAlignment = HorizontalAlignment.Center };
            canvas.UpdateAppearance(appearance);

            _showcase = personality.GetShowcaseAnimation();
            _animation = new CookieAnimationController(SpriteFrameCache.Catalog);
            _animation.OnSpriteFrameChanged += canvas.UpdateSpriteFrame;
            _animation.OnFrameChanged += canvas.UpdatePose;
            _animation.OnAnimationCompleted += _ => _animation.ForceAnimation(_showcase);
            _animation.ForceAnimation(_showcase);

            var label = new TextBlock
            {
                Text = personality.GetDisplayName(),
                HorizontalAlignment = HorizontalAlignment.Center,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(0, 2, 0, 0)
            };
            label.SetResourceReference(TextBlock.ForegroundProperty, "TextCharcoal");

            var stack = new StackPanel();
            stack.Children.Add(canvas);
            stack.Children.Add(label);

            _surface = new Border
            {
                CornerRadius = new CornerRadius(14),
                BorderThickness = new Thickness(1.5),
                Padding = new Thickness(6),
                Child = stack
            };

            var template = new ControlTemplate(typeof(Button))
            {
                VisualTree = new FrameworkElementFactory(typeof(ContentPresenter))
            };

            Button = new Button
            {
                Content = _surface,
                Template = template,
                Margin = new Thickness(4),
                Cursor = System.Windows.Input.Cursors.Hand,
                ToolTip = personality.GetSummary()
            };
            System.Windows.Automation.AutomationProperties.SetName(Button, personality.GetDisplayName());
            System.Windows.Automation.AutomationProperties.SetHelpText(Button, personality.GetSummary());

            SetSelected(false);
            Button.RenderTransformOrigin = new Point(0.5, 0.5);
            Button.RenderTransform = new ScaleTransform(1, 1);
            if (reduceMotion) _animation.RefreshFrame();
        }

        public void Update(double elapsed) => _animation.Update(elapsed);

        public void SetSelected(bool isSelected)
        {
            _surface.SetResourceReference(Border.BackgroundProperty, isSelected ? "CardSelected" : "BgIvory");
            _surface.SetResourceReference(Border.BorderBrushProperty, isSelected ? "AccentWarmOrange" : "BorderSubtle");

            if (Button.RenderTransform is ScaleTransform scale)
            {
                var spring = new DoubleAnimation(isSelected ? 1.04 : 1.0, TimeSpan.FromMilliseconds(220))
                {
                    EasingFunction = new BackEase { Amplitude = 0.5, EasingMode = EasingMode.EaseOut }
                };
                scale.BeginAnimation(ScaleTransform.ScaleXProperty, spring);
                scale.BeginAnimation(ScaleTransform.ScaleYProperty, spring);
            }
        }
    }
}
