# Cookie 🍪

A cute, premium desktop companion for macOS. Cookie is a little cat who
lives on your desktop — blinking, watching, and hopping when you say hello.

Native Swift app: **SwiftUI** for all UI, **SpriteKit** for the character.
Light theme, warm palette, no cloud, no accounts — everything stays local.

## Building

Requires Xcode with a full macOS SDK and [xcodegen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate          # regenerates Cookie.xcodeproj from project.yml
open Cookie.xcodeproj      # then Cmd+R, or:
xcodebuild -project Cookie.xcodeproj -scheme Cookie -configuration Debug build
```

If `xcodebuild` points at the Command Line Tools, prefix with
`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Project layout

```
Cookie/
    App/            App lifecycle: entry point, AppDelegate, composition root, WindowManager
    Models/         CookieProfile, personality, appearance, activity, statistics
    Cookie/         The desktop companion: panel, view controller, SpriteKit scene
    Animation/      SpriteProviding protocol, placeholder character, animation factory
    Behaviors/      CookieBehaviorEngine — decides what Cookie does next
    Customization/  Appearance/accessory catalog
    Persistence/    CookieStore — JSON persistence in Application Support
    Audio/          AudioManager — sound effects with gentle fallbacks
    MenuBar/        Menu bar menu
    Settings/       General / Appearance / Statistics tabs
    Views/          Welcome window and character preview
    ViewModels/     Welcome flow view model
    Resources/      Info.plist, Sounds/ (drop final audio here)
    Assets/         Asset catalog: accent color, app icon
scripts/make_icon.swift  Regenerates the placeholder app icon
project.yml              XcodeGen project definition
```

## Sprite animation system

The character is driven by `Animation/SpriteAnimationController`: a single
sprite node plays frame animations resolved from an ordered chain of
sources — bundle sprite sheets first, the rendered placeholder second —
so shipping final artwork means adding files, not changing code.

- **Catalog**: `CookieAnimationId` defines every animation (idle, blink,
  walk/run ×2 directions, sit, sleep, wake, stretch, yawn, groom, emotions,
  eat/drink, jump/fall/pickedUp/dropped, pet, meow) with priority, fps,
  and looping. Missing artwork falls back to idle automatically.
- **Priorities**: sleep < idle < walk < interaction < special. Higher
  priorities interrupt lower ones; one-shots finish into the previous
  looping base state automatically.
- **Direction**: one shared sheet per locomotion animation, mirrored at
  render time via a flip container — no separate left/right art.
- **Performance**: grid sheets are sliced with `SKTexture(rectIn:)` (one
  GPU texture), and placeholder poses are baked into textures once per
  palette and cached. Nothing is re-created per frame.
- **Accessibility**: with macOS Reduced Motion enabled, transitions and
  callbacks still occur but poses render statically.
- **Resource contract**: `Resources/Sprites/README.md` documents the
  `Sprites/Cookie/<Category>/` layout, the optional `manifest.json`
  (fps, loop, frame order, grid), and frame-numbering conventions.

The placeholder artwork is defined as parameterized poses
(`CookiePoseCatalog`) rendered by `CookieSpriteRenderer` into cached
textures, so it animates through the exact same pipeline final art will.

## Replacing the placeholder cat

Drop the final sheets into `Cookie/Resources/Sprites/Cookie/…` following
`Resources/Sprites/README.md`. The sheet source wins over the placeholder
automatically; `CookieScene`, the behavior engine, and persistence stay
untouched.

## Sound effects

Drop files named `cookie-pet` and `cookie-welcome` (`.aiff`/`.caf`/`.mp3`)
into the app bundle; `AudioManager` picks them up automatically and falls
back to soft system sounds until then.

## Data

One JSON file: `~/Library/Application Support/Cookie/cookie-store.json`.
Holds name, personality, appearance, accessories, unlocks, sound
preferences, companion position/visibility, and basic statistics. A file
that cannot be parsed is preserved as `cookie-store.json.unreadable`
rather than overwritten. Reset everything from Settings → Statistics.
