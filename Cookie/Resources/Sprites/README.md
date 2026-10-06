# Cookie Sprite Sheets

Final artwork for Cookie lives in this folder. The animation system
discovers it automatically — drop files in and they take precedence over
the built-in placeholder, with no code changes.

## Layout

    Sprites/Cookie/
        Idle/           idle, idleBlink, sit, stretch, yawn, groom
        Walk/           walk (mirrored for left/right)
        Run/            run (mirrored for left/right)
        Sleep/          sleep, wake
        Interaction/    eat, drink, pet, meow
        Emotions/       curious, happy, surprised, scared, annoyed, playful
        Special/        jump, fall, pickedUp, dropped

## Animations

| Sheet name | Loop    | FPS | Priority    |
| ---------- | ------- | --- | ----------- |
| idle       | yes     | 5   | idle        |
| idleBlink  | no      | 10  | idle        |
| sit        | yes     | 3   | idle        |
| stretch    | no      | 4   | idle        |
| yawn       | no      | 4   | idle        |
| groom      | no      | 5   | idle        |
| curious    | yes     | 4   | idle        |
| annoyed    | yes     | 4   | idle        |
| walk       | yes     | 7   | walk        |
| run        | yes     | 10  | walk        |
| happy      | no      | 6   | interaction |
| surprised  | no      | 6   | interaction |
| scared     | no      | 6   | interaction |
| playful    | yes     | 6   | interaction |
| eat        | yes     | 5   | interaction |
| drink      | yes     | 5   | interaction |
| pet        | no      | 6   | interaction |
| meow       | no      | 6   | interaction |
| sleep      | yes     | 2   | sleep       |
| wake       | no      | 4   | idle        |
| jump       | no      | 8   | special     |
| fall       | no      | 8   | special     |
| pickedUp   | yes     | 4   | special     |
| dropped    | no      | 8   | special     |

Priority ordering: sleep < idle < walk < interaction < special. A higher
priority interrupts a lower one; when a one-shot finishes, the previous
looping animation resumes automatically. Defaults above can be overridden
per animation with a manifest (see below).

## Two ways to provide frames

**1. Grid sheet (preferred)** — `<sheetName>.png` with transparent
background plus an optional `<sheetName>.json` manifest:

```json
{
    "grid": [4, 2],
    "fps": 8,
    "loop": false,
    "frames": [0, 1, 2, 3, 2, 1]
}
```

- `grid` — columns and rows of the sheet; frames are numbered left to
  right, top to bottom, starting at 0.
- `frames` — optional playback order (defaults to all frames in order);
  repeat indices to ping-pong.
- `fps` and `loop` override the table above.

**2. Numbered frames** — a folder named `<sheetName>/` containing
`frame0.png`, `frame1.png`, … in frame order. A `manifest.json` inside
the folder works the same way (omit `grid`).

## Conventions

- Transparent background, no padding between grid cells.
- All frames of one animation should share the same canvas size so the
  character does not jitter between frames.
- Left/right is handled by mirroring — provide `walk` once, not
  `walkLeft` and `walkRight`.
- Missing animations are not an error: the character falls back to idle
  until their artwork is added.
- Sheets ignore `CharacterPalette` (coloring is baked in). The palette
  only recolors the built-in placeholder.
