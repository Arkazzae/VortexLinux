# Vortex for Linux

[![Build status](https://github.com/Arkazzae/VortexLinux/actions/workflows/upstream-compatibility.yml/badge.svg)](https://github.com/Arkazzae/VortexLinux/actions/workflows/upstream-compatibility.yml)

![The folder Skyrim reads through Proton, C:\users\steamuser\Documents\My Games\Skyrim Special Edition, turns into the folder Vortex for Linux writes to: ~/.local/share/Steam/steamapps/compatdata/489830/pfx/drive_c/users/steamuser/Documents/My Games/Skyrim Special Edition](docs/hero.webp)

[Vortex](https://www.nexusmods.com/about/vortex/) is the mod manager from Nexus Mods, used for Skyrim, Fallout, Starfield, Baldur's Gate 3 and a few hundred other games. It's an Electron app, so it *technically* starts on Linux. But the usual workaround is running Vortex itself inside a Wine prefix, which is slow, fragile and annoying to set up.

This repo does the other thing: it patches Vortex to actually understand Linux, and builds it as a native app.

## What it does

- Finds native and Flatpak Steam libraries and selects the active game’s Proton prefix
- Maps `Documents` / `AppData` into the right prefix, so mods and saves land where the game actually looks
- Discovers Epic, GOG and Amazon games in native and Flatpak Heroic installations
- Launches games through Steam or Heroic
- Runs Windows modding tools in the game’s Wine/Proton prefix, including calls made by extensions
- Reads and writes Windows INI files while preserving encoding, comments and hardlinks
- Builds Bethesda plugin management with native Linux LOOT
- Deploys and purges hardlinked mods without leaving stale files behind
- Resolves Windows path casing consistently and keeps staging files safe when external changes are detected

These are general Linux fixes, not per-game hacks. Game-specific Vortex extensions can still carry their own Windows-only assumptions, so some games may still need fixes.

## Upstream is catching up 🎉

Vortex itself is slowly becoming more Linux-friendly. Since 2.7.1, the extension API's `util.epicGamesLauncher` is a shim over `GameStoreHelper` instead of `undefined` everywhere except Windows, so our Epic API fallback patch is gone 🎊.

2.9.0 goes further: Vortex now builds LOOT on Linux itself, with a libloot made for Linux, so we no longer compile libloot from source and our LOOT patch shrank to fixing file name casing and the Proton folder 🎉. Reading game versions from `.exe` files is plain TypeScript now too, so it works the same on every platform.

Every fix that lands upstream is one less patch to carry here, and the goal is for this repo to shrink.

## Games tested (confirmed working)

- Starfield
- Skyrim Special Edition
- Abiotic Factor
- Zero Sievert
- Baldur's Gate 3
- Cyberpunk 2077

## Install

Grab the [latest release](https://github.com/Arkazzae/VortexLinux/releases/latest). What changed in each release is in [CHANGELOG.md](CHANGELOG.md).

### Arch

```sh
sha256sum --check vortex-linux-*.pkg.tar.zst.sha256
sudo pacman -U ./vortex-linux-*.pkg.tar.zst
```

### Everything else (AppImage)

Install Wine from your package manager first, then:

```sh
sha256sum --check Vortex-*.AppImage.sha256
chmod +x Vortex-*.AppImage
./Vortex-*.AppImage
```

The AppImage bundles the Linux .NET 9 runtime Vortex probes for at startup, plus the Windows .NET runtimes modding tools need, so you don't need .NET installed system-wide. Wine you do need.

No FUSE 2 on your system? Run it as:

```sh
./Vortex-*.AppImage --appimage-extract-and-run
```

AppImages don't add themselves to your app menu; Gear Lever or AppImageLauncher handle that. For Nexus Mods download links, turn on "Handle Nexus Links" in Vortex: the AppImage then registers itself as the `nxm://` handler and keeps pointing at wherever the AppImage file is. This uses `xdg-settings` from xdg-utils, which desktop distributions ship with their browsers.

The AppImage embeds [AppImageUpdate](https://github.com/AppImageCommunity/AppImageUpdate) information pointing at this repository's latest release, so Gear Lever, AppImageLauncher and `appimageupdatetool` can check for and apply updates in place. Vortex also shows a notification when a newer Linux release is published; the older builds from `recipes/` stay pinned and never update.

## Before you add your first game

**Launch the game once through Steam or Heroic.** Proton and the game create their real config and save directories on that first run; if you point Vortex at a prefix that doesn't exist yet, nothing will line up.

**Keep staging and the game on the same filesystem.** Hardlinks can't cross filesystems. Vortex suggests a good folder under `Settings → Mods`. If you already have mods in an old staging folder, use Vortex's transfer flow. Don't move or delete it by hand.

The selected game determines which prefix Vortex uses. Steam’s per-game Proton
selection takes precedence over its default selection. Heroic’s game settings
select Wine, Proton or UMU; Flatpak tools run inside the Heroic Flatpak.

For a manually added Wine game, set `WINEPREFIX` in its environment settings.
`VORTEX_COMPAT_PREFIXES` can list additional prefixes, separated by colons, for
lookups without a selected game. If several prefixes match, Vortex reports the
ambiguity instead of choosing by modification time.

If Heroic is an AppImage outside `PATH`, set `HEROIC_BINARY` to its executable.
Launch it once before scanning for games. Linux-native Heroic games keep their
native configuration paths.

The separate prefix for Vortex’s own helper processes still defaults to
`${XDG_DATA_HOME:-$HOME/.local/share}/vortex-linux/wineprefix`.

## Building from source (Arch)

```sh
git clone https://github.com/Arkazzae/VortexLinux.git
cd vortex-linux
scripts/prepare-arch-build.sh
cd dist/arch-build
makepkg -si
```

The build pins Vortex to an exact upstream commit and downloads the source, Node dependencies, Electron and the Microsoft runtime files. First build is a big one.

Patches live in `patches/`, in the order listed by `_patches` in `PKGBUILD`.
`prepare-arch-build.sh` copies the packaging files and patches into
`dist/arch-build`, where makepkg keeps its sources and build output. Run it again
after changing patches or package metadata. `scripts/build-arch-package.sh`
prepares this directory automatically.

### Older Vortex versions

We support **1.16.9** and **2.6.2** for collections that need an older Vortex,
alongside the [latest release](https://github.com/Arkazzae/VortexLinux/releases/latest).
Need another version? [Open an issue](https://github.com/Arkazzae/VortexLinux/issues/new)
and tell us which version your collection needs.

To build one, fork this repo and run **Actions → Build a selected Vortex version**,
then download the files from the completed run. Or build locally on Arch:

```sh
python3 scripts/build-version.py --version 2.6.2
```

You'll find the files in `dist/versions/2.6.2/artifacts/`.

## How it's tested

Every change goes through the same pipeline before it can become a release:

1. **The patches apply.** CI checks out the pinned Vortex commit and applies every patch in order.
2. **The tests pass.** It runs the tests that ship with the patches, typechecks the renderer, and builds and tests the native LOOT binding.
3. **Both packages build.** The Arch package is built in a clean Arch container, and the AppImage is built from that package.
4. **The AppImage starts.** In a clean Ubuntu 24.04 container with Wine but no system .NET, it runs the bundled checks (the .NET probe, the Windows .NET runtimes through Wine, a FOMOD install, LOOT sorting, INI writes, prefix selection, Heroic discovery, tool arguments, hardlink purge), then boots Vortex under Xvfb and waits for the main page to render.

Only when all of that passes does a push to `master` publish a release, and only if that package revision has no complete release yet. The release notes come from [CHANGELOG.md](CHANGELOG.md): describe changes under *Unreleased*, and when `pkgrel` is bumped the release job files them under that revision and commits the result.

Every six hours a bot also looks for a new stable Vortex. If there is one, it runs the same pipeline against it. If everything passes, the bot bumps `PKGBUILD`, adds a changelog entry marked as an automatic update and publishes the release. If anything fails, nothing changes, and the bot opens or updates an issue naming the broken stage.

What this does not cover: launching a real game, Steam login, Flatpak permissions, every FOMOD dialog, or installing a whole collection. The game list above is what people reported working, not a test matrix.

### Run it yourself

```sh
scripts/test-appimage.sh dist/Vortex-*.AppImage             # the AppImage check
scripts/check-upstream-compatibility.sh --ref latest --keep  # patches against the newest Vortex
scripts/run-upstream-tests.sh /path/to/patched-vortex        # the test suite
```

`--ref pinned` checks the patches against the pinned version instead, and `--keep` keeps the prepared source for the test suite.

## Something broken?

Open an issue with the game, the store, where it's installed, how to reproduce it, and the relevant chunk of `~/.config/Vortex/vortex.log`. Scrub your Nexus tokens and private download links out of the log first.

## License

The build files and Linux patches here are GPL-3.0-only. Vortex itself stays under the upstream Nexus Mods license. See [LICENSE](LICENSE).
