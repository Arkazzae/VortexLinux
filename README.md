# Vortex for Linux

[![Build status](https://github.com/Arkazzae/vortex-linux/actions/workflows/upstream-compatibility.yml/badge.svg)](https://github.com/Arkazzae/vortex-linux/actions/workflows/upstream-compatibility.yml)

[Vortex](https://www.nexusmods.com/about/vortex/) is the mod manager from Nexus Mods — the one most people use for Skyrim, Fallout, Starfield, Baldur's Gate 3 and a few hundred other games. It's an Electron app, so it *technically* starts on Linux. But the usual workaround is running Vortex itself inside a Wine prefix, which is slow, fragile and annoying to set up.

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

These are general Linux fixes, not per-game hacks. Game-specific Vortex extensions can still carry their own Windows-only assumptions, so not every supported game is guaranteed to work — but the base is sane now.

## Upstream is catching up 🎉

Vortex itself is slowly becoming more Linux-friendly. Since 2.7.1, the extension API's `util.epicGamesLauncher` is a shim over `GameStoreHelper` instead of `undefined` everywhere except Windows, so our Epic API fallback patch is gone 🎊.

 Every fix that lands upstream is one less patch to carry here, and the goal is for this repo to shrink.

## Games tested (confirmed working)

- Starfield
- Skyrim Special Edition
- Abiotic Factor
- Zero Sievert
- Baldur's Gate 3
- Cyberpunk 2077

## Install

Grab the [latest release](https://github.com/Arkazzae/vortex-linux/releases/latest).

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

The AppImage bundles the Linux .NET 9 runtime Vortex probes for at startup, plus the Windows .NET runtimes modding tools need — you don't need .NET installed system-wide. Wine you do need.

No FUSE 2 on your system? Run it as:

```sh
./Vortex-*.AppImage --appimage-extract-and-run
```

AppImages don't add themselves to your app menu or register as the `nxm://` handler. AppImageLauncher handles that, or write a desktop entry yourself.

## Before you add your first game

**Launch the game once through Steam or Heroic.** Proton and the game create their real config and save directories on that first run; if you point Vortex at a prefix that doesn't exist yet, nothing will line up.

**Keep staging and the game on the same filesystem.** Hardlinks can't cross filesystems. Vortex suggests a good folder under `Settings → Mods`. If you already have mods in an old staging folder, use Vortex's transfer flow — don't move or delete it by hand.

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
git clone https://github.com/Arkazzae/vortex-linux.git
cd vortex-linux
scripts/prepare-arch-build.sh
cd dist/arch-build
makepkg -si
```

The build pins both Vortex and libloot to exact upstream commits and downloads the source, Node dependencies, Electron and the Microsoft runtime files. First build is a big one.

Patches live in `patches/`, in the order listed by `_patches` in `PKGBUILD`.
`prepare-arch-build.sh` copies the packaging files and patches into
`dist/arch-build`, where makepkg keeps its sources and build output. Run it again
after changing patches or package metadata. `scripts/build-arch-package.sh`
prepares this directory automatically.

### Building an older version

For collections that need a particular version, the builder uses its existing
Linux recipe and patches in a separate build directory. Local builds need Python
3.12+, Git, Arch Linux and the selected recipe's build dependencies.

```sh
python3 scripts/build-version.py --list
python3 scripts/build-version.py --version 2.6.2
```

Artifacts go to `dist/versions/2.6.2/artifacts/`. Use `--help` for format selection,
recipe inspection and choosing a packaging ref. Shallow clones need the full history.

You can also run **Actions → Build a selected Vortex version** and download the workflow artifacts.

Vortex 1.16.9 and 2.6.2 have maintained legacy recipes in `recipes/1.16.9/` and
`recipes/2.6.2/`. The 2.6.2 recipe includes native Linux LOOT and builds plugin
management together with Archive Check and Plugin Indexlock. Its AppImage check
verifies that all three extensions initialize without dependency failures.
Other historical recipes may need dependency updates; installed versions share
application data.

The version builder reads committed recipes and ignores local edits. To build
changes to the 2.6.2 recipe before committing them, run its scripts directly on
Arch with the dependencies listed in `recipes/2.6.2/.SRCINFO`:

```sh
recipes/2.6.2/scripts/build-arch-package.sh "$PWD/dist/legacy-2.6.2"
recipes/2.6.2/scripts/build-appimage.sh \
  "$PWD/dist/legacy-2.6.2/vortex-linux-2.6.2-x86_64.pkg.tar.zst" \
  "$PWD/dist/legacy-2.6.2"
recipes/2.6.2/scripts/test-appimage.sh \
  "$PWD/dist/legacy-2.6.2/Vortex-2.6.2-x86_64.AppImage"
```

The last command needs Docker and checks the artifact in a clean Ubuntu container.

## How it's tested

CI applies every patch, runs the affected tests, builds and tests native LOOT, and typechecks the renderer and plugin management. Changes on `master` build both release formats; an unpublished package revision publishes them together.

Every six hours, an unattended update job checks the newest stable upstream Vortex release. When it finds one, it applies the patches, runs their tests and renderer typechecking, builds both release formats, and boots the AppImage in a clean Ubuntu container. Only after every validation stage succeeds does the bot update `PKGBUILD` / `.SRCINFO` on `master` and publish the release. A validation or build failure leaves `master` and the current release untouched. Any failure opens or updates one issue with the broken stage; an interrupted publication is retried by the next scheduled run.

Before release, the AppImage is checked in a clean Ubuntu 24.04 container with
Wine and desktop libraries, without system .NET. The check runs the bundled
runtime probe, checks the bundled Windows .NET 6/8/10 inventory through Wine,
exercises an XML FOMOD installer, sorts fixture plugins with native
LOOT, and checks INI writes, prefix selection, Heroic discovery, tool arguments and
hardlink purge. It then starts Vortex under Xvfb and waits for its main page to
render.

These fixtures do not test a real game launch, Steam authentication, Flatpak
permissions, every FOMOD dialog or a complete collection install. The game list
above records earlier reports; it is not a test matrix for each new build.

Run the same artifact check locally:

```sh
scripts/test-appimage.sh dist/Vortex-*.AppImage
```

And test a new upstream release:

```sh
scripts/check-upstream-compatibility.sh --ref latest --keep
```

`--ref pinned` checks patch application against the pinned version. To run the
regression suite, keep the prepared source, install its dependencies and use:

```sh
scripts/run-upstream-tests.sh /path/to/patched-vortex
```

The suite also needs Rust to build the pinned libloot binding. See
[the comparison notes](docs/linux-project-comparison.md) for the projects reviewed
and the remaining gaps.

## Something broken?

Open an issue with the game, the store, where it's installed, how to reproduce it, and the relevant chunk of `~/.config/Vortex/vortex.log`. Scrub your Nexus tokens and private download links out of the log first.

## License

The build files and Linux patches here are GPL-3.0-only. Vortex itself stays under the upstream Nexus Mods license. See [LICENSE](LICENSE).
