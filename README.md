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

## Desktop companion behavior

The companion panel (`Cookie/CompanionPanelController.swift`) is a
borderless, non-activating `NSPanel` that floats above normal windows on
every Space, with no chrome — Cookie is not a document window:

- **Click-through**: `CompanionSKView.hitTest` consults
  `CookieHitTester`, a downsampled alpha silhouette of the artwork.
  Clicks on transparent pixels pass straight through to whatever app is
  beneath; only Cookie's actual shape (plus a 2-cell grab margin) is
  interactive. She never blocks the desktop around her.
- **Dragging**: grabbing Cookie pauses the activity cadence; dropping
  her clamps the position back into the visible screen area and persists
  it. A per-frame safety net re-clamps if a mouse-up is ever missed.
- **Walking**: the behavior engine picks personality-weighted strolls;
  `CookieScene.update(_:)` glides the panel at the personality's speed.
  At a screen edge she stops and turns around, idles, or sits near the
  edge — and walking stays suppressed for 25–50 s afterward, so she
  never ping-pongs between boundaries.
- **Screen safety**: `CookieScreenGeometry` keeps her center inside the
  union of all displays' visible frames. Saved positions stranded by a
  disconnected display fall back to the friendly default spot, and
  display-configuration changes / screen wake re-clamp automatically.
- **Window scanning**: `DesktopWindowScanner` is a read-only seam for
  future playful interactions (perching, glancing at windows). Cookie
  never modifies other applications' windows.
- **Debug**: `--export-cookie-hitmask` writes the clickable silhouette
  as PNG for review.

## Sprite animation system

The character is driven by `Animation/SpriteAnimationController`: a single
sprite node plays frame animations resolved from an ordered chain of
sources — bundle sprite sheets first, the shipped reference artwork
second, the rendered vector placeholder third.

**Current artwork**: the user's reference image ships as the `CookieArt`
asset and *is* the base pose (`ReferenceImageSource`). Every animation is
derived from it at runtime — bottom-anchored squash/tilt/bounce transforms
plus texture-cloned overlays (closed/happy/wide eyes, open mouth, boosted
blush) — so Cookie on screen always looks exactly like the reference.
Feature coordinates were measured from the artwork with
`scripts/analyze_reference.swift`; `scripts/prepare_reference.swift`
regenerates the trimmed asset and the app icon from the original PNG.

- **Catalog**: `CookieAnimationId` defines every animation (idle, blink,
  walk/run ×2 directions, sit, sleep, wake, stretch, yawn, groom, emotions,
  eat/drink, jump/fall/pickedUp/dropped, pet, meow) with priority, fps,
  and looping. Missing artwork falls back to idle automatically.
- **Priorities**: sleep < idle < walk < interaction < special. Higher
  priorities interrupt lower ones; one-shots finish into the previous
  looping base state automatically.
- **Direction**: one shared pose per locomotion animation, mirrored at
  render time via a flip container — no separate left/right art.
- **Performance**: grid sheets are sliced with `SKTexture(rectIn:)` (one
  GPU texture); derived frames are baked once per palette into cached
  textures. Nothing is re-created per frame.
- **Accessibility**: with macOS Reduced Motion enabled, transitions and
  callbacks still occur but poses render statically.
- **Resource contract**: `Resources/Sprites/README.md` documents the
  `Sprites/Cookie/<Category>/` layout, the optional `manifest.json`
  (fps, loop, frame order, grid), and frame-numbering conventions.
- **Debug tool**: run the app with `--export-cookie-frames` to write
  every baked frame as PNG (to `/tmp/cookie-frames`) for art review.

## Replacing or extending the artwork

Drop final animation sheets into `Cookie/Resources/Sprites/Cookie/…`
following `Resources/Sprites/README.md` — the sheet source outranks the
derived reference frames automatically, with no code changes. To swap the
base artwork instead, replace the `CookieArt` imageset and re-run
`scripts/prepare_reference.swift`.

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
