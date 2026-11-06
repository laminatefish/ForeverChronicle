# Forever Chronicle

A World of Warcraft: Forever addon that chronicles your character's journey. It draws the roads you've travelled on the world map, pins the moments that mattered, keeps a journal of your deeds, and holds your character's backstory, which you can share with other players.

## Features

- **Your route on the world map.** Every road you walk is drawn on the zone and continent maps, coloured from your first level to your last. Flight paths are dashed; hearthstones and portals show as faint dashed jumps.
- **Moments pinned where they happened.** Level-ups, deaths, dungeon entries, journal notes and where the journey began, each with a tooltip.
- **The journal.** Open it from the map tab on the character panel, the map button, or `/fc`.
  - *The Journey*: a timeline of everything that's happened, newest first.
  - *Deeds & Records*: level, days on the road, miles travelled, deaths, most dangerous place, most levels without dying.
  - *Backstory*: write who your character is, on parchment.
- **Route style.** Pick the route's colours with the game's colour picker, and its line width, from the map button.
- **Sharing** (opt-in, off by default). Players who also run Forever Chronicle see:
  - a book icon over your nameplate and "Has a backstory" in your tooltip, and can click to read it
  - your journey card in your tooltip: *3.2 miles travelled · Bested once · Day 2*

## Commands

| Command | |
|---|---|
| `/fc` | open or close the journal |
| `/fc note <text>` | write a journal entry pinned to where you stand |
| `/fc route` | show or hide the route on the world map |
| `/fc pause` / `/fc resume` | stop or restart recording |
| `/fc stats` | print your deeds and records |
| `/fc share` | start or stop sharing your backstory |
| `/fc card` | start or stop showing your journey card |
| `/fc read` | read your target's backstory |
| `/fc probe` | report what the game lets addons read here (useful in bug reports) |

`/chronicle` works too.

## Installing

Download the latest zip from [Releases](https://github.com/laminatefish/ForeverChronicle/releases) and unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, so you end up with `AddOns/ForeverChronicle/ForeverChronicle.toc`.

## Notes

- Routes are recorded every couple of seconds outdoors. Inside instances the game doesn't give addons your position, so events there are pinned at the last place you were outside.
- Records count from when the addon was installed on a character, not from level 1.
- Shared backstories are sent only when someone asks to read them, capped at about 4,000 characters, and shown to them as plain text. Other players' backstories are kept for the session only.
- With the controller (gamepad) interface on, the addon doesn't open the game's menus, colour picker or map itself, because doing so from an addon gets it blocked by the controller UI. The map button opens the journal instead.

## Releasing

Releases are built by the [BigWigs packager](https://github.com/BigWigsMods/packager) when a version tag is pushed:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The workflow fills in the version, builds `ForeverChronicle-v0.2.0.zip` and attaches it to a GitHub release. To upload to CurseForge and Wago as well, add `## X-Curse-Project-ID:` and `## X-Wago-ID:` to the `.toc` and set the `CF_API_KEY` and `WAGO_API_TOKEN` repository secrets.

## License

[MIT](LICENSE)
