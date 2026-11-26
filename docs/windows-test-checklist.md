# Testing Cookie on a real Windows PC

Cookie for Windows has only been built and tested on GitHub's build machines and on a Mac. These checks cover what
those can't: the installer, updating, the desktop itself, and the helpers. Allow about 45 minutes.

Use a Windows 10 (build 19041 or later) or Windows 11 PC, ideally one that has never had Cookie installed. Note
anything that looks wrong with a screenshot and the time it happened.

## 1. Install the old version, then update

This is the most important part: it's the path everyone who already has Cookie will take.

- [ ] Download **Cookie-Setup.exe** from the [1.1.0 release](https://github.com/MdKasif0/Cookie/releases/tag/v1.1.0)
      with Edge or Chrome, so Windows treats it as a download.
- [ ] Run it. Note what SmartScreen says (expected while the installer is unsigned: "Windows protected your PC",
      then **More info → Run anyway**).
- [ ] It installs without asking for an administrator password.
- [ ] Cookie appears on the desktop and in the tray, and **About** says 1.1.0.
- [ ] Change a few things (her name, coat, size) so you can tell later whether they survive the update.
- [ ] Wait about 15 seconds after she appears: the update window opens offering **1.4.0** with release notes.
- [ ] **Download & Install** shows progress, then **Launch Installer**. Cookie closes and the installer runs.
- [ ] After it finishes, **About** says 1.4.0, and the name, coat and size you set are kept.
- [ ] Start menu and desktop shortcuts still open Cookie, and there's only one Cookie in **Settings → Apps**.

## 2. Look and feel

- [ ] She walks, runs, sleeps, eats and stretches smoothly, with no flicker or black boxes around her.
- [ ] Petting, dragging and the right-click menu work. The purr keeps going while you pet her.
- [ ] Switch Windows between light and dark mode: Settings and menus follow.
- [ ] With two monitors, or with display scaling at 125% or 150%, she's sharp and stays on screen.
- [ ] Open a full-screen video or game: she steps aside. **Ctrl+Alt+C** calls her to the cursor.
- [ ] Share your screen in Teams, Zoom or Discord: she doesn't appear in what others see.

## 3. Helpers

- [ ] **Reminder** in 1 minute: she comes to the cursor and meows, even over a full-screen app.
- [ ] Turn on a **break nudge** with a short interval and check it arrives.
- [ ] **Focus guard**: add a distracting app, open it during a focus session, and she reacts.
- [ ] **Sticky note**: create, edit, move, restart Cookie, and the note is still there.
- [ ] **To-do list**: finish a task, and the bond goes up.
- [ ] **System watcher**: unplug a laptop's charger or turn off Wi-Fi, and she says so.
- [ ] **Downloads alert** (turn it on first): download a file, and she tells you when it finishes.
- [ ] **Screenshot tidy-up** (turn it on first): she offers to move old Desktop screenshots into
      Pictures\Screenshots, and nothing is deleted.
- [ ] **Drop a file** on her: move, copy and zip each work.
- [ ] **Clipboard history** (turn it on first): copied text shows up, and it's gone after you quit Cookie.
- [ ] **cookie:// links**: in Command Prompt, run `start cookie://summon`, and she comes to you.
- [ ] **Ask Cookie** (optional, needs your Claude API key): she answers. Quit and reopen, and the key is still
      saved (Credential Manager → Windows Credentials, as `Cookie/AnthropicApiKey`).

## 4. Settings and quitting

- [ ] Turn off **Automatically check for updates**, restart Cookie, and confirm no update window appears.
      (Fixed after 1.4.0. On 1.4.0 itself the window still appears.)
- [ ] **Start with Windows**: sign out and back in, and Cookie starts.
- [ ] **Quit** from the tray: nothing named Cookie is left in Task Manager.
- [ ] **Uninstall** from Settings → Apps: the app folder is removed. Note whether your settings in
      `%AppData%\Cookie` are kept, so you know what a reinstall will remember.

## If something goes wrong

- Crash or freeze: note the time, then open **Event Viewer → Windows Logs → Application** and look for an
  error from Cookie or .NET Runtime near that time.
- Update window says the update **could not be verified**: don't install from anywhere else; report it.
- Settings file: `%AppData%\Cookie\profile.json`.
