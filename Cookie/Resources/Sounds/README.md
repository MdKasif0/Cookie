# Cookie Sound Effects

These WAV files are designed by `scripts/make_sounds.py`, which models a cat's voice as a
pulsed vocal source shaped by moving formant filters, plus a small warm room. They are shared
by the macOS and Windows apps.

Recordings can replace any of them. Keep the file name, and delete the entry from `SOUNDS` in
the script so it won't be overwritten. `cookie-purr` must loop cleanly: both apps repeat it
for as long as she is purring.

| Effect      | File names                                            | Used for                               |
| ----------- | ----------------------------------------------------- | -------------------------------------- |
| Purr        | `cookie-purr` (a loop of about 9 seconds)             | Petting; continues while attention does |
| Meow        | `cookie-meow`, `cookie-meow-2`, `cookie-meow-3`       | Meows, mild protests                   |
| Happy       | `cookie-happy`, `cookie-happy-2`                      | The rising "mrrp!" on happy reactions  |
| Mew         | `cookie-mew`, `cookie-mew-2`                          | The shy reaction                       |
| Surprise    | `cookie-surprise`                                     | Nose taps, tail touches                |
| Eat         | `cookie-eat`                                          | Eating and drinking                    |
| Toy         | `cookie-toy`                                          | Play                                   |
| Drop        | `cookie-drop`                                         | Landing after being let go             |
| Chirp       | `cookie-chirp`                                        | Noticing the cursor nearby             |
| Sleep       | `cookie-sleep`                                        | Settling into a nap                    |
| Welcome     | `cookie-welcome`                                      | First-run greeting                     |

When an effect has several files, one is chosen at random without repeating the last. Meows
follow the Settings "Meow volume" slider, other effects follow the master volume, and sound can
be turned off entirely in Settings.
