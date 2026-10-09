# Playful Emote Artwork

## Overview
- **Identifier**: `playful`
- **Animation Sequence**: Cookie lowers into a pounce stance, wiggles left and right excitedly with wide eyes, pounces forward with happy paws, and lands gracefully.
- **Sound Effect**: `cookie-toy` (excited chirp / squeak)
- **Target Frame Rate**: 6 FPS
- **Playback**: One-shot (`loop: false`)

## Asset Drop-In
To supply final artwork:
- Option A: Place `playful.png` grid sheet in this directory along with grid dimensions in `emote.json`.
- Option B: Place `frame0.png`, `frame1.png`, etc. (180×180 pt transparent PNGs).

When no files are present, Cookie automatically executes the procedural playful bounce sequence derived from the reference artwork.
