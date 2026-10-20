<p align="center">
  <img src="Resources/icon.png" width="128" alt="Tunebar icon">
</p>

<h1 align="center">Tunebar</h1>

<p align="center">
  YouTube Music in your Mac's menu bar. Native, fast, and signed in to your own account.<br>
  <b><a href="https://github.com/sameetvipat/tunebar/releases/latest">Download Tunebar 1.0</a></b> · macOS 26 or later
</p>

## Features

- **Everything you use:** home, Explore (new releases, charts, moods & genres), search with
  suggestions, artists, albums, playlists, podcasts, uploads and your whole library
- **Now Playing** that grows out of the player card, with a **Song / Video** switch
- **Time-synced lyrics** where YouTube Music has them
- **Up Next** with Play Next, Add to Queue, drag to reorder, shuffle, repeat and Autoplay
- **Media keys and Control Center** show and control what's playing
- **Likes, playlists, subscriptions and your library:** create, edit and save without leaving the
  menu bar
- **Ad aware:** during an ad, skipping pauses until it ends, and **Skip** appears when YouTube offers it
- **Liquid Glass** design, keyboard shortcuts, and no Dock icon

## Install

1. Download `Tunebar-1.0.dmg` from the [latest release](https://github.com/sameetvipat/tunebar/releases/latest).
2. Open it and drag **Tunebar** to **Applications**.
3. Open Tunebar. macOS blocks apps from outside the App Store the first time: go to
   **System Settings → Privacy & Security** and click **Open Anyway**.
4. Tunebar opens from the **menu bar** at the top of your screen (it has no window or Dock icon).
   Click **Sign In** and sign in to Google. The sign-in window closes itself when you're done.

## Using Tunebar

| | |
|---|---|
| Open / close | Click the icon in the menu bar, or press **⌃⌥M** from any app |
| Play / pause | **Space** |
| Search | **⌘F** (click outside the box to close it) |
| Now Playing | Click the artwork on the player card · **Esc** to close |
| Lyrics, Up Next | The buttons on the player card or in Now Playing |
| Shuffle, repeat | In Now Playing · repeat cycles off → all → one |
| Media keys | ⏯ ⏮ ⏭ on your keyboard, AirPods and Control Center |
| More actions | Right-click a song, album or playlist, or use its **⋯** button |
| Account | Your photo in the top bar · Sign Out is there |
| Reload, Quit | Right-click the menu bar icon |

## FAQ

**macOS says Tunebar "can't be opened".**
Tunebar isn't from the App Store, so macOS asks you to allow it once. Open
**System Settings → Privacy & Security** and click **Open Anyway**, then open Tunebar again.

**I opened it and nothing appeared.**
Tunebar lives in the menu bar, not in a window. Look for its icon near the clock at the top of your
screen, or press **⌃⌥M**.

**Google asks for a passkey and it doesn't work.**
Passkeys only work in Safari and other browsers Apple approves. Click **Try another way**, then
choose a prompt on your phone or your password.

**Do I need YouTube Premium?**
No. Free accounts hear ads like on the website. Tunebar notices them and pauses track skipping until
they end. With Premium there are no ads.

**Why are lyrics or Video greyed out for some songs?**
Lyrics appear only where YouTube Music has them, and they're time-synced when available. They're off
while a video plays. Video is off for songs that have no music video.

**Does music keep playing when I close it?**
Yes. Closing the popover only hides it. Play, pause and skip from your keyboard's media keys or
Control Center.

**Why is there a short gap between songs that should flow into each other?**
YouTube Music's website loads every track separately, so it can't play albums gaplessly the way its
phone app can. Tunebar keeps the gap as short as the website allows.

**Something stopped working.**
YouTube Music sometimes changes its website. Right-click the menu bar icon and choose **Reload**. If
that doesn't fix it, please [open an issue](https://github.com/sameetvipat/tunebar/issues).

**How do I quit or uninstall it?**
Right-click the menu bar icon and choose **Quit**. To uninstall, drag Tunebar from Applications to
the Bin, and delete the folders listed under Privacy to remove your sign-in.

## Privacy

No servers, no analytics, no tracking. Tunebar only talks to YouTube, like a browser tab. You sign
in on Google's own page, and your sign-in stays on your Mac, in:

```
~/Library/HTTPStorages/com.local.ytmusictray*
~/Library/WebKit/com.local.ytmusictray
~/Library/Caches/com.local.ytmusictray
```

Errors are logged to `~/Library/Logs/Tunebar.log`.

## Build from source

Needs the Xcode Command Line Tools (`xcode-select --install`).

```sh
Scripts/build.sh      # builds Tunebar.app
Scripts/package.sh    # builds dist/Tunebar-<version>.dmg
TUNEBAR_SELFTEST=1 ./Tunebar.app/Contents/MacOS/Tunebar   # checks it still works with YouTube Music
```

```
Sources/Tunebar/
  App/        launch, menu bar item, popover, sign-in window
  Player/     the hidden YouTube Music page and everything it does
  Models/     songs, pages, queue items, lyrics
  Views/      the popover: top bar, pages, player card, Now Playing, components
  Support/    logging and small helpers
  Testing/    the self-test
Resources/    bridge.js (talks to the YouTube Music page), app icon
Scripts/      build, package and icon scripts
```

Tunebar runs YouTube Music's website in a hidden window, and `Resources/bridge.js` is the part that
talks to it.

---

Not affiliated with Google or YouTube. YouTube Music is a trademark of Google LLC.
