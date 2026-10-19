# Tunebar

YouTube Music in your Mac's menu bar. Click the icon, search, play, and get back to work: no
browser tab to keep open.

It's a native app with a Liquid Glass design: your home feed, search, your library (playlists,
songs, liked songs, albums, artists, history), Up Next with autoplay, likes, mixes and the media
keys. The music itself comes from your own YouTube Music account.

Requires macOS 26 or later.

## Install

1. Open `Tunebar-1.0.dmg` and drag **Tunebar** onto **Applications**.
2. Open it. The first time, macOS will say it can't verify the developer, because the app isn't
   signed by Apple. Go to **System Settings → Privacy & Security**, scroll down, and click
   **Open Anyway**. You only do this once.
3. Sign in: right-click the menu bar icon, choose **Show Web Player (Sign In)**, sign in to your
   Google account, and close the window. You stay signed in from then on.

To start it automatically, add it in **System Settings → General → Login Items**.

## Using it

- **Click the icon**, or press **⌃⌥M** anywhere, to open the player. Click outside it to close it.
- **Space** plays and pauses. **⌘F** searches. The **speaker** button mutes and sets the volume.
- **Right-click** any song, album or playlist for Play Next, Add to Queue, Start Mix, Add to
  Playlist, Add to Library, Share and more.
- **Share** any song, album, playlist or artist from its ⋯ menu: send it with Messages, Mail or
  AirDrop, or **Copy Link**. Links open on any device, in a browser or the YouTube Music app.
- **‹ ›** next to a shelf's title scrolls it sideways (a trackpad swipe works too).
- **Hover over artwork** and click ▶ to play an album, playlist or song without opening it.
- **Click an artist or album name** to go to its page. Album pages show the release date, label
  and description. Click the artwork in the player for the album or playlist it's playing from.
- **👍** likes a song and **👎** dislikes it, from the player, any song row or Up Next.
- In **Up Next**, **Clear** empties your queue. With **Autoplay** on, similar songs keep playing
  after it; with it off, playback stops at the end of the current song.
- On your own playlists, **Edit** changes the name, description and privacy, reorders songs by
  dragging, or deletes the playlist. **Select** removes several songs at once, from your playlists,
  Liked songs or your library.
- **Right-click the menu bar icon** for Reload and Quit.

## Privacy and your account

Tunebar has no servers, no analytics and no tracking. It never sees your Google password, and
it doesn't send anything anywhere except to YouTube, exactly like a browser tab would.

- **Signing in** happens on Google's own sign-in page, inside the web player window. You type
  your password into Google, not into Tunebar.
- **What stays on your Mac** is the same kind of data a browser keeps after you sign in: Google's
  sign-in cookies and the YouTube Music website's own storage. macOS's web engine keeps it in your
  user account, only readable by you (the folder names come from the app's earlier working name):
  - `~/Library/HTTPStorages/com.local.ytmusictray` (cookies, including the sign-in)
  - `~/Library/WebKit/com.local.ytmusictray` (the website's local storage)
  - `~/Library/Caches/com.local.ytmusictray` (cached images and pages)
- **What it connects to:** YouTube Music and Google's servers for music and artwork. Nothing else.
- **The only file Tunebar writes itself** is `~/Library/Logs/Tunebar.log`, which records errors
  (for example "couldn't add to playlist") so problems can be traced. It never contains your
  password or cookies.

To sign out, sign out in the web player (right-click the icon → **Show Web Player**). To remove
everything Tunebar has stored, quit it and delete the folders above, or run:

```sh
rm -rf ~/Library/HTTPStorages/com.local.ytmusictray* ~/Library/WebKit/com.local.ytmusictray \
       ~/Library/Caches/com.local.ytmusictray ~/Library/Logs/Tunebar.log
```

The full source is included, so all of this can be checked: the part that talks to YouTube is
`Resources/bridge.js`.

## If something stops working

The app is built on YouTube Music's website, and Google changes that from time to time. If
something breaks after an update, **Reload** (right-click the icon) usually helps. Problems are
logged to `~/Library/Logs/Tunebar.log`.

## Building from source

You need the Xcode Command Line Tools (`xcode-select --install`); full Xcode isn't required.

```sh
./build.sh       # builds Tunebar.app
./package.sh     # builds it and makes dist/Tunebar-<version>.dmg
```

To check that everything still works against the live site (signed out, muted, without touching
your account):

```sh
TUNEBAR_SELFTEST=1 ./Tunebar.app/Contents/MacOS/Tunebar
```

The code is in `Sources/Tunebar`, in numbered folders from the app's entry point (`00-App`)
through the model, the player and the views, to the self-test (`05-Testing`).
`Resources/bridge.js` is the script that runs inside the YouTube Music page.

---

Tunebar is an independent project. It isn't affiliated with or endorsed by Google or YouTube.
YouTube Music is a trademark of Google LLC.
