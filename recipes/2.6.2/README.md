# Vortex 2.6.2 for Linux

Maintained Linux recipe for upstream v2.6.2, including native LOOT plugin
management, Gamebryo Archive Check and Gamebryo Plugin Indexlock.

From the packaging repository, build the committed recipe with:

```sh
python3 scripts/build-version.py --version 2.6.2
```

To build local recipe changes before committing them:

```sh
recipes/2.6.2/scripts/build-arch-package.sh "$PWD/dist/legacy-2.6.2"
recipes/2.6.2/scripts/build-appimage.sh \
  "$PWD/dist/legacy-2.6.2/vortex-linux-2.6.2-x86_64.pkg.tar.zst" \
  "$PWD/dist/legacy-2.6.2"
```

Run the artifact checks on the resulting AppImage:

```sh
recipes/2.6.2/scripts/test-appimage.sh \
  "$PWD/dist/legacy-2.6.2/Vortex-2.6.2-x86_64.AppImage"
```

The checks exercise native LOOT sorting and metadata, the bundled runtimes and
FOMOD installer, then start Vortex with a fresh profile and verify that all three
Gamebryo extensions are enabled without load failures. They do not replace a
full collection install or a real game launch.
