# Wave Emote Artwork

## Overview
- **Identifier**: `wave`
- **Animation Sequence**: Cookie turns towards the user, lifts a front paw, waves it side-to-side with happy eyes and rosy blush, then lowers her paw smoothly.
- **Sound Effect**: `cookie-welcome` (welcome chirp)
- **Target Frame Rate**: 6 FPS
- **Playback**: One-shot (`loop: false`)

## Asset Drop-In
To supply final artwork:
- Option A: Place `wave.png` grid sheet in this directory along with grid dimensions in `emote.json`.
- Option B: Place `frame0.png`, `frame1.png`, `frame2.png`, etc. (180×180 pt transparent PNGs).

When no files are present, Cookie automatically executes the procedural wave sequence derived from the reference artwork in `ReferenceImageSource` and `CookiePoseCatalog`.
