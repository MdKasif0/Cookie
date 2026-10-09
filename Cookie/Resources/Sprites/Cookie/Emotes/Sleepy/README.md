# Sleepy Emote Artwork

## Overview
- **Identifier**: `sleepy`
- **Animation Sequence**: Cookie gives a slow, drowsy blink, yawns with mouth open wide, curls down with closed eyes, and settles into a comfortable drowsy tuck.
- **Sound Effect**: `cookie-sleep` (gentle soft breathing / yawn sigh)
- **Target Frame Rate**: 4 FPS
- **Playback**: One-shot (`loop: false`)

## Asset Drop-In
To supply final artwork:
- Option A: Place `sleepy.png` grid sheet in this directory along with grid dimensions in `emote.json`.
- Option B: Place `frame0.png`, `frame1.png`, etc. (180×180 pt transparent PNGs).

When no files are present, Cookie automatically executes the procedural sleepy sequence derived from the reference artwork.
