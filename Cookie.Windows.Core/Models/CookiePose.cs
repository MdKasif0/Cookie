namespace Cookie.Windows.Core.Models;

public enum CookieEyeStyle
{
    Open,
    Wide,
    Half,
    Happy,
    Closed
}

public enum CookieMouthStyle
{
    Smile,
    Flat,
    Open,
    OpenWide
}

public enum CookieEarStyle
{
    Normal,
    Back
}

public struct CookiePose
{
    public double Squash { get; set; } = 1.0;
    public double BodyY { get; set; } = 0.0;
    public double HeadX { get; set; } = 0.0;
    public double HeadY { get; set; } = 0.0;
    public double HeadTilt { get; set; } = 0.0;
    public double TailAngle { get; set; } = 0.0;
    public double PawOffsetX { get; set; } = 0.0;
    public double PawLift { get; set; } = 0.0;
    public CookieEarStyle EarStyle { get; set; } = CookieEarStyle.Normal;
    public CookieEyeStyle EyeStyle { get; set; } = CookieEyeStyle.Open;
    public CookieMouthStyle MouthStyle { get; set; } = CookieMouthStyle.Smile;
    public double BlushScale { get; set; } = 1.0;
    public double GazeX { get; set; } = 0.0;

    public CookiePose()
    {
    }

    public CookiePose(
        double squash = 1.0,
        double bodyY = 0.0,
        double headX = 0.0,
        double headY = 0.0,
        double headTilt = 0.0,
        double tailAngle = 0.0,
        double pawOffsetX = 0.0,
        double pawLift = 0.0,
        CookieEarStyle earStyle = CookieEarStyle.Normal,
        CookieEyeStyle eyeStyle = CookieEyeStyle.Open,
        CookieMouthStyle mouthStyle = CookieMouthStyle.Smile,
        double blushScale = 1.0,
        double gazeX = 0.0)
    {
        Squash = squash;
        BodyY = bodyY;
        HeadX = headX;
        HeadY = headY;
        HeadTilt = headTilt;
        TailAngle = tailAngle;
        PawOffsetX = pawOffsetX;
        PawLift = pawLift;
        EarStyle = earStyle;
        EyeStyle = eyeStyle;
        MouthStyle = mouthStyle;
        BlushScale = blushScale;
        GazeX = gazeX;
    }
}
