# Changelog

What changed in each Vortex for Linux release, newest first. Describe changes
under *Unreleased* as they land. When `pkgrel` is bumped, the release workflow
moves those notes into a section named after the package revision
(`<Vortex version>-<package release>`), commits it and uses it as the GitHub
release notes; `scripts/changelog.py release --revision <revision>` does the
same by hand. The unattended update job writes its own section when it
publishes a new Vortex version, taking any pending notes with it.

## Unreleased

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
