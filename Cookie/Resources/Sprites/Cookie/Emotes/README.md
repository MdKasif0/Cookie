# Cookie Emote Sprites & Asset Checklist

This directory houses dedicated animation sequences, frame artwork, thumbnails, and metadata for Cookie's user-triggered emotes.

## Directory Layout

```
Resources/
    Sprites/
        Cookie/
            Emotes/
                Wave/       Cookie says hello (paw wave & friendly meow)
                Happy/      Cookie is feeling happy (bounces & soft mrrp!)
                Love/       Cookie sends you some love (affection & floating peach heart)
                Sleepy/     Cookie needs a little nap (yawn, curl up & gentle nap breath)
                Playful/    Cookie wants to play (wiggle & playful pounce)
```

## Emote Asset Status & Checklist

Below is the formal status report for each of the five emotes in accordance with the Asset Fallback Strategy:

| Emote | Existing Assets Used | Missing Sprite Frames | Bundled Audio Assets | Animation Status |
| :--- | :--- | :--- | :--- | :--- |
| **Wave** | • `CookieArt` (reference image)<br>• Procedural paw wave overlay & head tilt | Dedicated frame sequence or grid sheet (`wave.png` or `frame0.png`…`frame11.png`) | `cookie-mew.wav` / `cookie-chirp.wav` | **Provisional** (Active reference-derived animation with sampled arm/paw wave overlay & joyful expression) |
| **Happy** | • `CookieArt` (reference image)<br>• `cookie-eyes-close` reference | Dedicated jump/squash-and-stretch frames (`happy.png` or `frame0.png`…`frame10.png`) | `cookie-happy.wav` | **Provisional** (Active reference-derived animation with double joyful bounce & blush boost) |
| **Love** | • `CookieArt` (reference image)<br>• SpriteKit peach heart vector | Dedicated affection/cuddle frames (`love.png` or `frame0.png`…`frame9.png`) | `cookie-purr.wav` | **Provisional** (Active reference-derived animation with gentle lean, closed eyes & floating peach heart) |
| **Sleepy** | • `CookieArt` (reference image)<br>• `cookie-sleep` reference<br>• SpriteKit "z" indicator | Dedicated yawn & stretch frames (`sleepy.png` or `frame0.png`…`frame15.png`) | `cookie-sleep.wav` | **Provisional** (Active reference-derived animation with multi-phase yawn, nap breathing & stretch) |
| **Playful** | • `CookieArt` (reference image)<br>• `cookie-mischievous` reference | Dedicated pounce/wiggle frames (`playful.png` or `frame0.png`…`frame10.png`) | `cookie-toy.wav` | **Provisional** (Active reference-derived animation with crouch wiggle & contained pounce) |

---

## How Asset Replacement Works

The animation pipeline prioritizes assets in this exact order:

1. **Dedicated Sprite Sheets or Numbered Frames (Highest Priority)**:
   - Placed in `Sprites/Cookie/Emotes/<EmoteName>/`
   - E.g., `wave.png` grid sheet or `frame0.png`, `frame1.png`, …
   - Configured via `emote.json` or `manifest.json`.
2. **Reference Image Animation (Built-in Active Pipeline)**:
   - When dedicated frames are not yet provided, `ReferenceImageSource` uses the shipped Cookie reference character artwork (`CookieArt`) to bake bottom-anchored procedural transform sequences and feature overlays (`.eyesClosed`, `.eyesHappy`, `.blushBoost`, `.pawWave`, etc.).
3. **Placeholder Vector Rigs (Last Resort Fallback)**:
   - When no image artwork is present, `PlaceholderVectorSource` renders vector pose sequences defined in `CookiePoseCatalog`.

## Two Ways to Provide Dedicated Artwork

### Option 1: Uniform Grid Sheet (Recommended)
Place `<name>.png` (or `sheet.png`) with a transparent background in the folder, paired with an `emote.json`:
```json
{
  "fps": 6,
  "loop": false,
  "grid": [4, 3],
  "frames": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
  "sound": "cookie-mew"
}
```

### Option 2: Numbered Frames
Place `frame0.png`, `frame1.png`, `frame2.png`, etc. directly inside the folder. An optional `emote.json` specifies timing:
```json
{
  "fps": 6,
  "loop": false,
  "frames": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
}
```

## Artwork Specifications
- **Canvas Size**: 180×180 points (or 360×360 px @2x retina).
- **Format**: 32-bit RGBA PNG with transparent background.
- **Character Consistency**: Preserve Cookie's exact silhouette, eye size, facial geometry, paw design, and warm cream/ivory color palette.
- **Looping**: Must be `false` for one-shot emotes so Cookie naturally returns to autonomous idle behavior upon completion.
