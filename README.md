# Vortex for Linux

[![Build status](https://github.com/Arkazzae/VortexLinux/actions/workflows/upstream-compatibility.yml/badge.svg)](https://github.com/Arkazzae/VortexLinux/actions/workflows/upstream-compatibility.yml)
[![Latest release](https://img.shields.io/github/v/release/Arkazzae/VortexLinux?label=release)](https://github.com/Arkazzae/VortexLinux/releases/latest)

![The folder Skyrim reads through Proton, C:\users\steamuser\Documents\My Games\Skyrim Special Edition, turns into the folder Vortex for Linux writes to: ~/.local/share/Steam/steamapps/compatdata/489830/pfx/drive_c/users/steamuser/Documents/My Games/Skyrim Special Edition](docs/hero.webp)

[Vortex](https://www.nexusmods.com/about/vortex/) is the mod manager from Nexus Mods, used for Skyrim, Fallout, Starfield, Baldur's Gate 3 and a few hundred other games. It's an Electron app, so it *technically* starts on Linux. But the usual workaround is running Vortex itself inside a Wine prefix, which is slow, fragile and annoying to set up.

This repo does the other thing: it patches Vortex to actually understand Linux, and builds it as a native app.

**[Install](#install)** · [Before your first game](#before-you-add-your-first-game) · [Build it yourself](#building-from-source) · [Report a bug](#something-broken)

## What works

- **Steam**, native or Flatpak. Vortex finds your libraries and each game's Proton prefix.
- **Heroic**, native or Flatpak, with your Epic, GOG and Amazon games.
- **Lutris and Bottles**, as an [experiment](#lutris-and-bottles-experimental).
- **Files land where the game looks.** `Documents` and `AppData` map into the game's prefix, so saves, INI files and plugin lists end up in the right place.
- **Windows modding tools** such as xEdit or BodySlide run in the game's own Wine or Proton prefix.
- **LOOT** sorts Bethesda plugins natively.
- **Deploy and purge** use hardlinks and leave no stale files behind.

Vortex itself runs as a normal Linux app: the interface, downloads, FOMOD installers, deployment and LOOT. Only the Windows-only tools go through Wine.

> [!NOTE]
> These are general Linux fixes, not per-game hacks. A game's own Vortex extension can still assume Windows here and there, so some games may need a fix of their own.

## Upstream is catching up 🎉

Vortex itself keeps getting better at Linux. Since 2.9 it builds LOOT for Linux on its own, and 2.10 fixed staging folders on mounted drives, installers that use backslashes and the greyed-out `nxm://` setting. Every fix that lands upstream is one less patch to carry here. The goal is for this repo to shrink.

## Install

Download the file for your distribution from the [latest release](https://github.com/Arkazzae/VortexLinux/releases/latest). [CHANGELOG.md](CHANGELOG.md) says what changed.

| Distribution | Install with |
|---|---|
| Arch | `sudo pacman -U ./vortex-linux-*.pkg.tar.zst` |
| Debian 13+, Ubuntu 24.04+ | `sudo apt install ./vortex-linux_*_amd64.deb` |
| Fedora 43+ | `sudo dnf install ./vortex-linux-*-x86_64.rpm` |
| openSUSE Leap 16, Tumbleweed | `sudo zypper install --allow-unsigned-rpm ./vortex-linux-*-x86_64.rpm` |
| Anything else | the [AppImage](#appimage) |

The package manager pulls in Wine and everything else Vortex needs, and Vortex shows up in your app menu. You never have to install .NET yourself. Vortex tells you when a newer release is out; install it the same way.

Every file has a `.sha256` next to it, and `sha256sum --check <file>.sha256` verifies the download. The RPM isn't signed, which is why zypper needs `--allow-unsigned-rpm`.

> [!NOTE]
> Debian 12 and Ubuntu 22.04 are too old. Vortex's FOMOD installer needs glibc 2.38, and that goes for the AppImage too.

### AppImage

Install Wine from your package manager first, then:

```sh
chmod +x Vortex-*.AppImage
./Vortex-*.AppImage
```

.NET is inside the AppImage, so Wine is the only thing you install yourself. Gear Lever or AppImageLauncher add it to your app menu and can update it in place (so can `appimageupdatetool`).

For the download buttons on Nexus Mods, turn on **Handle Mod Manager Download buttons** in Vortex's settings. Vortex then registers the AppImage for `nxm://` links and keeps that pointing at the file wherever you put it. This needs `xdg-utils`, which desktop distributions already ship.

> [!TIP]
> No FUSE 2 on your system? Start it with `./Vortex-*.AppImage --appimage-extract-and-run`.

## Before you add your first game

1. **Start the game once from Steam or Heroic.** That first run is when Proton creates the prefix and the game creates its config and save folders. Until they exist, Vortex has nothing to line up with.
2. **Keep the staging folder on the same filesystem as the game.** Mods are deployed as hardlinks, and hardlinks can't cross filesystems. `Settings → Mods` suggests a folder that works.

> [!CAUTION]
> Don't move or delete a staging folder that already has mods in it by hand. Change the path in `Settings → Mods` and let Vortex move the mods.

### Which Wine prefix Vortex uses

The prefix follows the game you've selected: its Proton prefix on Steam, the Wine, Proton or UMU you set up in Heroic, the Lutris prefix, or the bottle. Tools run with the same Wine or Proton. A game you added by hand starts in Wine's default prefix, `$WINEPREFIX` or `~/.wine`, and Linux-native games from Heroic keep their native paths.

`Game settings → Wine` shows the prefix in use and lets you choose another. Steam, Heroic, Lutris and Bottles still start their games in their own prefix, so a different folder there only moves the game's INI and plugin files and where tools run.

Vortex's own Windows helpers, and tools started with no game selected, use a separate prefix in `~/.local/share/vortex-linux/wineprefix`.

A few environment variables help when Vortex can't find something:

| Variable | Set it when |
|---|---|
| `HEROIC_BINARY` | Heroic is an AppImage outside `PATH`. Open it once before Vortex scans for games. |
| `LUTRIS_BINARY` | `lutris` isn't on `PATH` |
| `BOTTLES_CLI_BINARY` | `bottles-cli` isn't on `PATH` |
| `VORTEX_COMPAT_PREFIXES` | you want more prefixes searched when no game is selected (colon-separated). If several match, Vortex says so instead of guessing. |

### Lutris and Bottles (experimental)

Both are new and lightly tested, so please report what breaks.

If Vortex doesn't find the game by itself, set its folder by hand, as it appears inside the Lutris prefix or the bottle (a symlink to another disk is fine). Vortex recognises whose game it is, uses that prefix, starts the game through the launcher and runs tools with the Wine version chosen there.

- **Lutris:** tools need a Wine runner for now. Games set to Proton can be deployed to and launched, but can't run tools.
- **Bottles:** the folder of a program you added to a bottle works too. Bottles are looked up by name, so rename any that share one. Flatpak Bottles only sees the folders its sandbox allows.

## Building from source

On Arch:

```sh
git clone https://github.com/Arkazzae/VortexLinux.git
cd VortexLinux
scripts/prepare-arch-build.sh
cd dist/arch-build
makepkg -si
```

The build pins Vortex to an exact upstream commit and downloads its source, the Node dependencies, Electron and the Microsoft runtimes. The first build takes a while.

### Older Vortex versions

Some collections need an older Vortex, so **1.16.9** and **2.6.2** are supported next to the latest release. They stay on their version and never update. Need a different one? [Open an issue](https://github.com/Arkazzae/VortexLinux/issues/new) and say which version your collection asks for.

To get one, fork this repo, run **Actions → Build a selected Vortex version** and download the files from the finished run. Or build it locally:

```sh
python3 scripts/build-version.py --version 2.6.2
```

The files end up in `dist/versions/2.6.2/artifacts/`.

## How it's tested

Nothing becomes a release until CI has applied every patch to the pinned Vortex commit, run the tests and built every package. Each package is then installed in a clean container of every distribution it supports, with no system .NET, and put to work: a FOMOD install, LOOT sorting, INI writes, a hardlink purge, Windows tools through Wine. Vortex has to boot, render its main page and uninstall cleanly.

To run the same checks yourself:

```sh
scripts/test-package.sh dist/Vortex-*.AppImage              # the AppImage check
scripts/test-package.sh dist/vortex-linux-*.rpm fedora:44    # a package on one distribution
scripts/check-upstream-compatibility.sh --ref latest --keep  # patches against the newest Vortex
scripts/run-upstream-tests.sh /path/to/patched-vortex        # the test suite
```

`--ref pinned` checks against the pinned version instead, and `--keep` keeps the prepared source for the test suite.

## Something broken?

[Open an issue](https://github.com/Arkazzae/VortexLinux/issues/new) with the game, the store, where it's installed, how to reproduce it, and the relevant part of `~/.config/Vortex/vortex.log`.

> [!WARNING]
> Remove your Nexus tokens and private download links from the log before you post it.

## Thanks

Most of what got fixed here started as somebody's bug report. The people behind those reports and pull requests are in [THANKS.md](THANKS.md).

## License

The build files and Linux patches here are GPL-3.0-only. Vortex itself stays under the upstream Nexus Mods license. See [LICENSE](LICENSE).
