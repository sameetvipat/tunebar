<p align="center">
  <img src="Resources/icon.png" width="128" alt="Tunebar icon">
</p>

<h1 align="center">Tunebar</h1>

<p align="center">
  YouTube Music in your Mac's menu bar. Native SwiftUI, Liquid Glass, your own account.<br>
  <b><a href="https://github.com/sameetvipat/tunebar/releases/latest">Download the latest release</a></b> · macOS 26 or later
</p>

## Install

1. Open the DMG and drag **Tunebar** to **Applications**.
2. First launch: macOS blocks unsigned apps. Click **Open Anyway** in
   **System Settings → Privacy & Security**.
3. Right-click the menu bar icon → **Show Web Player (Sign In)**, sign in to Google, close the window.

## Shortcuts

| | |
|---|---|
| Open / close | Click the icon, or **⌃⌥M** anywhere |
| Play / pause | **Space** |
| Search | **⌘F** |
| Song, album and playlist actions | Right-click, or the **⋯** button |
| Reload, Quit | Right-click the menu bar icon |

## Privacy

No servers, no analytics, no tracking. Tunebar only talks to YouTube, like a browser tab.
You sign in on Google's own page; the sign-in stays on your Mac in:

```
~/Library/HTTPStorages/com.local.ytmusictray*
~/Library/WebKit/com.local.ytmusictray
~/Library/Caches/com.local.ytmusictray
```

Delete those folders to remove everything. Errors are logged to `~/Library/Logs/Tunebar.log`.

## Build

Needs the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh      # Tunebar.app
./package.sh    # dist/Tunebar-<version>.dmg
TUNEBAR_SELFTEST=1 ./Tunebar.app/Contents/MacOS/Tunebar   # checks it still works with YouTube Music
```

Tunebar runs YouTube Music's website in a hidden window; `Resources/bridge.js` is the part that
talks to it. If Google changes the site and something breaks, **Reload** usually fixes it.

---

Not affiliated with Google or YouTube. YouTube Music is a trademark of Google LLC.
