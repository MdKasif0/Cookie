# Cookie Emote Sprites

This directory houses dedicated animation sequences, frame artwork, thumbnails, and metadata for Cookie's user-triggered emotes.

## Directory Layout

```
Resources/
    Sprites/
        Cookie/
            Emotes/
                Wave/       Friendly greeting paw wave
                Happy/      Joyful jump and blush purr
                Love/       Shy, heart-melting affectionate nuzzle
                Sleepy/     Cozy stretch, yawn, and curl up
                Playful/    Excited wiggle and hop
```

## How Asset Replacement Works

The animation pipeline prioritizes assets in this exact order:

1. **Dedicated Sprite Sheets or Numbered Frames (Highest Priority)**:
   - Placed in `Sprites/Cookie/Emotes/<EmoteName>/`
   - E.g., `wave.png` grid sheet or `frame0.png`, `frame1.png`, …
   - Configured via `emote.json` or `manifest.json`.
2. **Reference Image Animation (Built-in Fallback)**:
   - When dedicated frames are not yet provided, `ReferenceImageSource` uses the shipped Cookie reference character artwork (`CookieArt`) to bake bottom-anchored procedural transform sequences and feature overlays.
3. **Placeholder Vector Rigs (Last Resort)**:
   - When no image artwork is present, `PlaceholderVectorSource` renders vector pose sequences defined in `CookiePoseCatalog`.

## Two Ways to Provide Dedicated Artwork

### Option 1: Uniform Grid Sheet (Recommended)
Place `<name>.png` (or `sheet.png`) with a transparent background in the folder, paired with an `emote.json`:
```json
{
  "fps": 6,
  "loop": false,
  "grid": [4, 2],
  "frames": [0, 1, 2, 3, 2, 1],
  "sound": "cookie-welcome"
}
```

### Option 2: Numbered Frames
Place `frame0.png`, `frame1.png`, `frame2.png`, etc. directly inside the folder. An optional `emote.json` specifies timing:
```json
{
  "fps": 6,
  "loop": false,
  "frames": [0, 1, 2, 3]
}
```

## Guidelines
- **Canvas Size**: 180×180 points (or 360×360 px @2x retina).
- **Background**: Transparent PNG.
- **Looping**: Must be `false` for one-shot emotes so Cookie naturally returns to her autonomous resting state upon completion.
