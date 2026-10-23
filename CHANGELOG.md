# Changelog

What changed in each Vortex for Linux release, newest first. Describe changes
under *Unreleased* as they land. When `pkgrel` is bumped, the release workflow
moves those notes into a section named after the package revision
(`<Vortex version>-<package release>`), commits it and uses it as the GitHub
release notes; `scripts/changelog.py release --revision <revision>` does the
same by hand. The unattended update job writes its own section when it
publishes a new Vortex version, taking any pending notes with it.

## Unreleased

- Experimental: games installed through Lutris' Wine runner are recognised.
  Point Vortex at the game folder and it deploys into the game's Lutris prefix,
  starts the game through Lutris and runs modding tools with the game's Wine
  build. GOG and Epic games from Lutris' services are also found when a game
  extension looks them up by store ID.
- Experimental: games installed in a Bottles bottle are recognised the same
  way. A game folder inside a bottle, or one holding a program added to a
  bottle, uses that bottle as its prefix, starts through `bottles-cli` and runs
  tools with the bottle's runner.
- The 2.6.2 recipe carries the Linux fixes from 2.8.2-3 through 2.9.0-3:
  extension config paths, deployment preflight and target logging, extensions
  behind a symlinked home, differently cased game paths, backslash archive
  paths, nxm:// links from the AppImage, mixed-case deployment folders and the
  default Wine prefix. The 1.16.9 recipe gets the last three. (#16, #20, #22)
- Building the package, also with the 1.16.9 and 2.6.2 recipes, no longer
  downloads QuickBMS from altervista.org: the server refuses the download and
  on some networks the request hung until the build was interrupted. The
  "Build a selected Vortex version" workflow works again on a fork; Git refused
  to read the checkout inside the build container. (#24)

## 2.9.0-3 - 2026-10-23

- A game added by hand, outside Steam and Heroic, runs in Wine's default
  prefix (`$WINEPREFIX` or `~/.wine`) instead of failing with "The game's Wine
  prefix is unavailable". The message now also says where to set a different
  prefix: edit the game on the Dashboard, Environment Variables. (#22)

## 2.9.0-2 - 2026-10-22

- Mods whose archives use Windows backslashes between folders install
  correctly. Vortex can also remove a leftover `.installing` folder, and mods
  that earlier releases installed with backslashes in their file names, instead
  of reporting them as "open in another application". (#16)
- Folders that mods spell in different case, such as `textures` and
  `Textures`, are deployed into one folder. Vortex created both when it linked
  their files at the same time, and the game found only one of them. (#20)

## 2.9.0-1 - 2026-10-19

- Vortex 2.9.0.
- LOOT uses the native binding that now comes with Vortex itself instead of
  one built from libloot's sources, so building the package no longer needs
  Rust. It is the same libloot version, 0.29.6.
- Mods whose archives use Windows backslashes between folders, such as
  Appearance Runtime Plugin for Cyberpunk 2077, install into those folders
  instead of as one file named after the whole path. (#16)
- The AppImage handles "Mod Manager Download" links from the Nexus Mods
  website. With "Handle Nexus Links" on, it adds its own hidden desktop entry
  for nxm:// links, since an AppImage installs none. (#18)

## 2.8.2-4 - 2026-10-16

- Extensions you install work when the Vortex settings folder is reached
  through a symlink, such as `/home` on Fedora Atomic or a `~/.config/Vortex`
  moved to another disk. They can load the modules bundled with Vortex (Elden
  Ring failed with "Cannot find module 'turbowalk'"), and an error in one shows
  the extension error notice instead of closing Vortex. (#14)
- Game files that an extension names in a different letter case from the
  install are found, such as Elden Ring's executable in its `Game` folder, so
  the game is recognised, starts and reports its version. (#15)

## 2.8.2-3 - 2026-10-15

- The AppImage embeds AppImageUpdate information and every release now ships a
  `.zsync` file, so Gear Lever, AppImageLauncher and `appimageupdatetool` can
  update it in place. (#13)
- The AppImage bundles AppStream metadata, and its `X-AppImage-Version` carries
  the package revision instead of just the Vortex version.
- Deploying a Windows-only mod type such as Local AppData config no longer
  creates an empty copy of the target folder on the Linux side; the files were
  already going into the Proton prefix, and `vortex.log` now records which
  folder each mod type deploys to. (#11)
- Vortex 1.16.9 and 2.6.2 can be built on demand from `recipes/` for
  collections that need an older Vortex. These pinned builds never update.
- Links and the in-app release check point at the renamed VortexLinux
  repository.
- Releases get their notes from this changelog.

## 2.8.2-2 - 2026-10-14

- Game extensions that read or write `%LOCALAPPDATA%`, `%APPDATA%` or
  `Saved Games` paths through Node's `fs` are redirected into the selected
  game's Proton profile, so config and save mod types deploy there.
- Deployment stops with a clear message before linking anything when a mod
  type has no target folder.

## 2.8.2-1 - 2026-10-13

Automatic update to Vortex 2.8.2.

## 2.8.1-1 - 2026-10-12

Automatic update to Vortex 2.8.1.

## 2.8.0-2 - 2026-10-10

- Proton config paths resolve correctly for deployment and purge.
- The AppImage runtime checks run reliably on a clean Ubuntu container.

## 2.8.0-1 - 2026-10-07

Vortex 2.8.0 with the Linux patches ported to the new release. Earlier
releases are described on their GitHub release pages.
