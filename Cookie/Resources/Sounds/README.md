# Cookie Sound Effects

Place Cookie's final sound effects in this folder. `AudioManager` looks
them up by name in the app bundle:

| Effect   | File name (any of .aiff/.caf/.mp3/.wav) |
| -------- | --------------------------------------- |
| Petting  | `cookie-pet`                            |
| Welcome  | `cookie-welcome`                        |

Until real audio ships, each effect falls back to a gentle macOS system
sound, so interaction feedback is never missing. Sound preferences
(enabled, volume) live in the persistent store and apply automatically.
