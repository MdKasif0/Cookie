using System;
using Cookie.Windows.Core.Models;

namespace Cookie.Windows.Core.Animation;

public class CookieAnimationController
{
    private CookieAnimationId _currentAnimationId = CookieAnimationId.Idle;
    private CookieAnimationSpec _currentSpec = CookieAnimationId.Idle.GetSpec();
    private CookiePose[] _currentFrames = CookiePoseCatalog.GetFrames("idle") ?? new[] { new CookiePose() };
    private int _currentFrameIndex = 0;
    private double _frameTimer = 0.0;
    private CookieDirection _facingDirection = CookieDirection.Right;
    private double _animationIntensity = 1.0;

    private double _dynamicGazeX = 0.0;
    private double _dynamicHeadTilt = 0.0;

    public event Action<CookiePose, CookieDirection>? OnFrameChanged;
    public event Action<CookieAnimationId>? OnAnimationCompleted;

    public CookieAnimationId CurrentAnimationId => _currentAnimationId;
    public CookieAnimationPriority CurrentPriority => _currentSpec.Priority;
    public CookieDirection FacingDirection => _facingDirection;
    public double AnimationIntensity
    {
        get => _animationIntensity;
        set => _animationIntensity = Math.Clamp(value, 0.5, 1.5);
    }

    public CookieAnimationController()
    {
        SetAnimation(CookieAnimationId.Idle, force: true);
    }

    public bool PlayAnimation(CookieAnimationId animationId, bool interruptIfLowerOrEqual = false)
    {
        var newSpec = animationId.GetSpec();

        if (newSpec.Priority < _currentSpec.Priority)
        {
            return false;
        }

        if (newSpec.Priority == _currentSpec.Priority && !interruptIfLowerOrEqual && _currentAnimationId == animationId)
        {
            return false;
        }

        SetAnimation(animationId);
        return true;
    }

    public void SetFacing(CookieDirection direction)
    {
        if (_facingDirection != direction)
        {
            _facingDirection = direction;
            NotifyCurrentFrame();
        }
    }

    public void SetLookAt(double gazeX, double headTilt)
    {
        _dynamicGazeX = Math.Clamp(gazeX, -5.0, 5.0);
        _dynamicHeadTilt = Math.Clamp(headTilt, -8.0, 8.0);
        NotifyCurrentFrame();
    }

    public void ResetLookAt()
    {
        _dynamicGazeX = 0.0;
        _dynamicHeadTilt = 0.0;
        NotifyCurrentFrame();
    }

    public void Update(double deltaTimeSeconds)
    {
        if (_currentFrames.Length == 0) return;

        double effectiveFps = _currentSpec.Fps * _animationIntensity;
        double frameDuration = 1.0 / Math.Max(effectiveFps, 1.0);

        _frameTimer += deltaTimeSeconds;

        if (_frameTimer >= frameDuration)
        {
            int framesToAdvance = (int)(_frameTimer / frameDuration);
            _frameTimer %= frameDuration;

            int nextIndex = _currentFrameIndex + framesToAdvance;

            if (nextIndex >= _currentFrames.Length)
            {
                if (_currentSpec.IsLooping)
                {
                    _currentFrameIndex = nextIndex % _currentFrames.Length;
                }
                else
                {
                    var completedId = _currentAnimationId;
                    _currentFrameIndex = _currentFrames.Length - 1;
                    OnAnimationCompleted?.Invoke(completedId);

                    SetAnimation(CookieAnimationId.Idle, force: true);
                    return;
                }
            }
            else
            {
                _currentFrameIndex = nextIndex;
            }

            NotifyCurrentFrame();
        }
    }

    private void SetAnimation(CookieAnimationId animationId, bool force = false)
    {
        if (!force && _currentAnimationId == animationId && _currentSpec.IsLooping)
        {
            return;
        }

        _currentAnimationId = animationId;
        _currentSpec = animationId.GetSpec();

        if (_currentSpec.Direction.HasValue)
        {
            _facingDirection = _currentSpec.Direction.Value;
        }

        var frames = CookiePoseCatalog.GetFrames(_currentSpec.SheetName);
        _currentFrames = frames ?? CookiePoseCatalog.GetFrames("idle") ?? new[] { new CookiePose() };
        _currentFrameIndex = 0;
        _frameTimer = 0.0;

        NotifyCurrentFrame();
    }

    private void NotifyCurrentFrame()
    {
        if (_currentFrames.Length == 0) return;

        var basePose = _currentFrames[Math.Clamp(_currentFrameIndex, 0, _currentFrames.Length - 1)];

        if (Math.Abs(_dynamicGazeX) > 0.001 || Math.Abs(_dynamicHeadTilt) > 0.001)
        {
            basePose.GazeX += _dynamicGazeX;
            basePose.HeadTilt += _dynamicHeadTilt;
        }

        OnFrameChanged?.Invoke(basePose, _facingDirection);
    }
}
