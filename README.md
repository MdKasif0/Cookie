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

## Replacing the placeholder cat

The current character is a temporary vector-drawn cat
(`Animation/CookieCharacterNode.swift`). Everything downstream talks to the
`SpriteProviding` protocol (`Animation/SpriteProviding.swift`):

```swift
protocol SpriteProviding: SKNode {
    var activity: CookieActivity { get }
    func startIdling()
    func setActivity(_ activity: CookieActivity)
    func playPetReaction()
    func apply(palette: CharacterPalette)
}
```

To ship the final artwork, add an `SKTextureAtlas`-backed conformer that
maps `CookieActivity` cases (`.idle`, `.watching`, `.delighted`) to frame
sequences and return it from `CookieScene` — the scene, behavior engine,
persistence, and all UI stay untouched. `CookieScene` is the only place
that constructs the character.

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
