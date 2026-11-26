using System;
using System.Linq;
using Cookie.Windows.Core.Desktop;
using Cookie.Windows.Core.Helpers;
using Cookie.Windows.Core.Models;
using Cookie.Windows.Views;

namespace Cookie.Windows.Desktop;

/// <summary>The helpers tour: a few steps in a card beside her, each one something you can try right away.</summary>
public partial class CompanionWindow
{
    private TourWindow? _tour;

    /// <summary>From her menu or the tray: always available, and brings her back if she was hidden.</summary>
    public void StartHelpersTour()
    {
        if (_quiet?.IsQuiet == true) return;
        if (!IsVisible) Show();
        BeginTour();
    }

    /// <summary>Starts the tour by itself only once, and only at a calm moment; otherwise it waits for another launch.</summary>
    private void OfferTourIfDue()
    {
        if (!HelpersTour.CanStartOnItsOwn(
                _profile.Settings.HasCompletedOnboarding,
                _profile.HasSeenHelpersTour,
                IsVisible,
                _quiet?.IsQuiet == true,
                _focus.IsFocusing))
            return;
        BeginTour();
    }

    private void BeginTour()
    {
        if (_tour?.IsRunning == true) return;
        if (_tour == null)
        {
            _tour = new TourWindow { VisibleArea = WorkAreaAroundCookie };
            ScreenSharingGuard.Apply(_tour, _profile.Settings.HideFromScreenSharing);
            _tour.StepShown = step =>
            {
                _behaviorController.React(step.Reaction);
                _audioManager.Play(SoundEffect.Chirp);
            };
            _tour.ActionChosen = action =>
            {
                switch (action)
                {
                    case HelpersTour.TourAction.NewReminder: NewReminder(); break;
                    case HelpersTour.TourAction.PinNote: AddStickyNote(HelpersTour.SampleNote); break;
                    case HelpersTour.TourAction.OpenPowerTools: OpenSettingsWindow(SettingsTab.PowerTools); break;
                }
            };
            _tour.Ended = finished =>
            {
                _profile.HasSeenHelpersTour = true;
                _settingsManager.DebouncedSave(_profile);
                if (finished)
                {
                    _behaviorController.React(CookieAnimationId.Happy);
                    _audioManager.Play(SoundEffect.Happy);
                }
            };
        }
        _bubble?.HideNow();
        _tour.Start(HelpersTour.Steps(_profile.DisplayName), this);
    }

    /// <summary>The work area of the screen she's on, so the card never covers the taskbar.</summary>
    private CoreRect WorkAreaAroundCookie()
    {
        double cx = Left + Width / 2, cy = Top + Height / 2;
        var monitors = _screenService.GetActiveMonitors();
        var here = monitors.FirstOrDefault(m => cx >= m.MonitorBounds.Left && cx < m.MonitorBounds.Right
                                             && cy >= m.MonitorBounds.Top && cy < m.MonitorBounds.Bottom);
        return here?.WorkArea ?? _screenService.GetPrimaryWorkArea();
    }

    /// <summary>Where a new note should keep clear of: her, plus the tour card while it's up.</summary>
    private CoreRect NoteAnchorWithTour(CoreRect anchor) =>
        _tour?.IsRunning == true && _tour.IsVisible ? HelpersTour.Union(anchor, _tour.Bounds) : anchor;
}
