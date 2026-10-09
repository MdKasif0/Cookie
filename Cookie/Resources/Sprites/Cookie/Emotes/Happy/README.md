# Happy Emote Artwork

## Overview
- **Identifier**: `happy`
- **Animation Sequence**: Cookie dips down slightly in anticipation, springs up into an enthusiastic bounce with joyful curved eyes and bright cheeks, lands gently, and settles.
- **Sound Effect**: `cookie-happy` (cheerful rising chirp)
- **Target Frame Rate**: 6 FPS
- **Playback**: One-shot (`loop: false`)

## Asset Drop-In
To supply final artwork:
- Option A: Place `happy.png` grid sheet in this directory along with grid dimensions in `emote.json`.
- Option B: Place `frame0.png`, `frame1.png`, etc. (180×180 pt transparent PNGs).

When no files are present, Cookie automatically executes the procedural happy bounce sequence derived from the reference artwork.
