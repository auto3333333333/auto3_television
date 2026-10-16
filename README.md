# rensyu_television

[日本語版はこちら](README.ja.md)

TVs and boomboxes for FiveM. Everything is synced for every player.

- Watch **YouTube / Twitch** videos and live streams on TVs (volume follows distance, late joiners start at the same position)
- Broadcast YouTube / Twitch as server-wide **channels** (fixed channels, shared channels, and channels players open themselves)
- Show and **interact with web pages** using the mouse
- Show images / videos / audio files from direct links
- **Boombox**: an `ox_inventory` item that places a prop and plays sound from it
- Tablet-style UI, multi-language (English / Japanese included)

## Requirements
| Resource | |
|---|---|
| `ox_lib` | required |
| `ox_target` | optional (without it a TextUI prompt + keybind is used) |
| `ox_inventory` | only for the boombox item |

## Installation
1. Put `rensyu_television` in your `resources` folder.
2. `server.cfg`:
   ```
   setr ox:locale en            # or ja
   ensure ox_lib
   ensure ox_target             # optional
   ensure rensyu_television
   add_ace group.admin rensyu_television.broadcast allow   # who may broadcast to channels
   ```
3. If you used the original `generic_texture_renderer_gfx` resource, **remove it**: the same files are bundled in `stream/`.
4. Boombox: add the item from `install/ox_inventory_items.lua` to ox_inventory's `data/items.lua`.

## Language
The language follows the `ox:locale` convar. English (`en`) and Japanese (`ja`) are included.
To add a language, copy `locales/en.json` to `locales/<code>.json` and translate the values.
Pull requests with new translations are welcome.

## Supported links
YouTube: `watch?v=`, `youtu.be/`, `shorts/`, `live/`, `embed/`, playlists, `channel/UC...` (live), `?t=90` start times.
Twitch: channels, `popout/` / `embed/` links, VODs (`/videos/123`, `?t=1h2m3s`), clips (`clips.twitch.tv/`, `.../clip/`), `player.twitch.tv/?channel=`.
Anything else is treated as a web page, image, video or audio link.

## Using it
- **TV**: target a TV with ox_target ("Use TV"), or use `/tv`. Without ox_target a prompt appears and the ox_lib keybind (default `E`, rebindable in the FiveM key settings) opens it.
- The tablet UI has a collapsing sidebar: *Remote*, *Channels*, *Presets*, *History*.
  - Remote: now playing, pause / seek / restart / re-sync, source type, URL, volume, "Interact", power off
  - Channels: tune the TV, or broadcast (if you have permission)
  - History: shows the **title** of each page / video (looked up by the server and cached)
- **Interact**: the screen opens in a window (the game stays visible around it) drawn on the top layer; use the mouse to click / scroll. Close with the **×** button or `Esc`.
- `/broadcast` opens the broadcast manager away from any TV.
- `/tvmodel` prints the model hash of the nearest object, to help you add missing TV models.

### Channels
- Channels with a `url` in `Config.Channels` are **fixed** (nobody can overwrite them).
- Channels without a `url` are shared: anyone with broadcast permission can use them.
- Players with permission can open **their own channel** (named CH 01, CH 02, ...). It closes when they leave.
- TVs show a `CH 01` overlay and a notice when a channel starts / ends.

### Boombox
1. Use the `boombox` item: a prop is placed in front of you (the item is consumed).
2. Target it to open the player: YouTube / Twitch / audio files, **sound only**. Pause, seek, restart, stop, volume.
3. "Pick up" returns the item (`Config.Boombox.PickupAnyone` decides who may).
- Sound fades with distance, is muffled by walls and is completely silent from sealed rooms (see `Config.Occlusion`).
- Up to `Config.Boombox.MaxActive` boomboxes play at once (nearest first).
- Your character plays an animation while the boombox panel is open (`Config.Boombox.Animation`, set to `false` to disable).

## Configuration
Everything is in `config.lua` (commented): distances, volume, permissions (ACE), approval hooks, banned words,
channels, presets, TV models, placed TVs, boombox, YouTube language, page titles.

## Security notes
- All input is validated and cooldown-limited on the server; only `http(s)` URLs are accepted. Use `Config.BannedWords` / `Config.BlockedHosts` and `Config.Hooks` for your own rules.
- **Page titles**: the server requests the URL to read its `<title>` (YouTube uses oEmbed, media files use the file name).
  Requests to localhost / private addresses are refused, but a hostname that *resolves* to a private address cannot be detected.
  If that matters for you, set `Config.Titles.FetchWeb = false` (or `Enabled = false`).

## Limitations
- GTA V shares one screen between all TV models with the same render target name (e.g. `tvscreen`): only the last-used / nearest one is drawn.
  Use a different model, or the 3D mode (`Target = nil` + `Offset` / `Scale`) in `Config.TVModels`, for one picture per TV.
- Web interaction is mouse-only (FiveM DUIs cannot receive keyboard input). Clicks only affect the player who made them.
- Pause / seek only works for videos, YouTube videos, Twitch VODs and audio files (not live streams / web / images).
- Unofficial features (YouTube audio-track selection, `Config.TVModels` entries marked as guesses) may not work everywhere.
- Videos whose owners **disabled embedding** (YouTube error 101/150), and Twitch clips, are opened as the normal YouTube / Twitch page instead. They play, but volume-by-distance and pause / seek sync do not work on those pages (use "Interact" to click on the page).
- HLS (.m3u8) and other formats the browser cannot play directly are not supported.
- Boomboxes are not saved across a server restart (items are returned to online owners when the resource stops).
- `Config.Titles`: titles of ordinary web pages depend on the site allowing the request.

## Licensing
Code, locales and UI: MIT (see `LICENSE`).
`stream/generic_texture_renderer*.gfx` are third-party assets (a Scaleform movie by its original author) and are **not** covered by that license.
Check that you may redistribute them before publishing the repository, or ask users to download them from the original source.
