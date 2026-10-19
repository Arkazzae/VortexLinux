# Maintainer: Arkazzae <https://github.com/Arkazzae>

pkgname=vortex-linux
pkgver=2.9.0
pkgrel=1
pkgdesc="Community build of Vortex with generic Linux compatibility patches"
arch=('x86_64')
url="https://github.com/Arkazzae/VortexLinux"
license=('GPL-3.0-only')

depends=(
  'alsa-lib'
  'at-spi2-core'
  'cairo'
  'cups'
  'dotnet-runtime'
  'gtk3'
  'fontconfig'
  'libappindicator'
  'libdrm'
  'libnotify'
  'libsecret'
  'libx11'
  'libxcb'
  'libxcomposite'
  'libxdamage'
  'libxext'
  'libxfixes'
  'libxkbcommon'
  'libxrandr'
  'libxss'
  'mesa'
  'nss'
  'pango'
  'wine'
  'wine-mono'
  'xdg-utils'
)
makedepends=(
  'dotnet-sdk'
  'git'
  'node-gyp'
  'nodejs-lts-krypton'
  'npm'
  'patchelf'
  'python'
  'python-setuptools'
  'yarn'
)

_activate_upstream_pnpm() {
  cd "$srcdir/vortex"

  local expected_pnpm
  expected_pnpm="$(
    node -p '(/^pnpm@([^+]+)/.exec(require("./package.json").packageManager ?? "") ?? [, ""])[1]'
  )"
  if [[ ! "$expected_pnpm" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    printf 'Unable to determine the pnpm version required by upstream\n' >&2
    return 1
  fi
  if [[ "$expected_pnpm" != "$_pnpm" ]]; then
    printf 'Upstream requires pnpm %s, but PKGBUILD provides %s\n' \
      "$expected_pnpm" "$_pnpm" >&2
    return 1
  fi

  local pnpm_root="$srcdir/pnpm-cli-$_pnpm"
  local pnpm_bin="$pnpm_root/package/bin"
  if [[ ! -f "$pnpm_bin/pnpm.cjs" ]]; then
    mkdir -p "$pnpm_root"
    bsdtar -xf "$srcdir/pnpm-$_pnpm.tgz" -C "$pnpm_root"
  fi
  if [[ ! -f "$pnpm_bin/pnpm.cjs" ]]; then
    printf 'The pnpm %s source archive is incomplete\n' "$_pnpm" >&2
    return 1
  fi
  chmod 755 "$pnpm_bin/pnpm.cjs"
  ln -sfn pnpm.cjs "$pnpm_bin/pnpm"
  export PATH="$pnpm_bin:$PATH"

  local actual_pnpm
  actual_pnpm="$("$pnpm_bin/pnpm" --version)" || return 1
  if [[ "$actual_pnpm" != "$expected_pnpm" ]]; then
    printf 'Upstream requires pnpm %s, but the source archive provides %s\n' \
      "$expected_pnpm" "$actual_pnpm" >&2
    return 1
  fi
}
optdepends=(
  'kde-cli-tools: native trash support on KDE Plasma'
  'pipewire: screen sharing under Wayland'
)
provides=("vortex=${pkgver}")
conflicts=('vortex' 'vortex-bin' 'vortex-git')
options=('!debug' '!strip')
install=vortex.install

_upstream_commit='e04093000d0f6ccf78994670599f7a42b361a038'
_pnpm='11.10.0'
_dotnet6='6.0.36'
_dotnet8='8.0.29'
_dotnet10='10.0.10'
_patches=(
  '0001-linux-runtime-compatibility.patch'
  '0002-linux-path-and-executable-discovery.patch'
  '0003-linux-filesystem-and-deployment.patch'
  '0004-linux-extension-dependency-handling.patch'
  '0005-linux-steam-game-launch.patch'
  '0006-linux-optional-ini-purge.patch'
  '0007-linux-posix-hardlink-purge.patch'
  '0008-linux-proton-user-folders.patch'
  '0009-linux-staging-suggestions.patch'
  '0010-download-state-recovery.patch'
  '0011-linux-case-safe-deployment.patch'
  '0012-linux-extension-path-compatibility.patch'
  '0013-linux-win32-normalize-compatibility.patch'
  '0015-linux-dotnet-game-version.patch'
  '0016-linux-gamebryo-archive-support.patch'
  '0017-linux-preserve-vortex-userdata.patch'
  '0018-linux-ini-support.patch'
  '0019-linux-game-prefix-selection.patch'
  '0020-linux-native-loot.patch'
  '0021-linux-game-tool-runners.patch'
  '0022-linux-heroic-stores.patch'
  '0023-linux-native-build.patch'
  '0024-linux-artifact-self-test.patch'
  '0025-linux-new-game-config.patch'
  '0026-linux-tool-file-arguments.patch'
  '0027-linux-release-notifications.patch'
  '0028-linux-atomic-config-writes.patch'
  '0029-linux-prefix-config-purge.patch'
  '0030-linux-extension-config-paths.patch'
  '0031-linux-deployment-preflight.patch'
  '0032-linux-deployment-target-paths.patch'
  '0033-linux-symlinked-extension-paths.patch'
  '0034-linux-case-only-platform-paths.patch'
)

source=(
  "vortex::git+https://github.com/Nexus-Mods/Vortex.git#commit=${_upstream_commit}"
  "pnpm-${_pnpm}.tgz::https://registry.npmjs.org/pnpm/-/pnpm-${_pnpm}.tgz"
  "${_patches[@]}"
  'vortex.sh'
  'vortex.desktop'
  'README.md'
  'LICENSE'
  "dotnet-runtime-${_dotnet6}-win-x64.zip::https://builds.dotnet.microsoft.com/dotnet/Runtime/${_dotnet6}/dotnet-runtime-${_dotnet6}-win-x64.zip"
  "dotnet-runtime-${_dotnet8}-win-x64.zip::https://builds.dotnet.microsoft.com/dotnet/Runtime/${_dotnet8}/dotnet-runtime-${_dotnet8}-win-x64.zip"
  "dotnet-runtime-${_dotnet10}-win-x64.zip::https://builds.dotnet.microsoft.com/dotnet/Runtime/${_dotnet10}/dotnet-runtime-${_dotnet10}-win-x64.zip"
  "windowsdesktop-runtime-${_dotnet6}-win-x64.zip::https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/${_dotnet6}/windowsdesktop-runtime-${_dotnet6}-win-x64.zip"
  "windowsdesktop-runtime-${_dotnet8}-win-x64.zip::https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/${_dotnet8}/windowsdesktop-runtime-${_dotnet8}-win-x64.zip"
  "windowsdesktop-runtime-${_dotnet10}-win-x64.zip::https://builds.dotnet.microsoft.com/dotnet/WindowsDesktop/${_dotnet10}/windowsdesktop-runtime-${_dotnet10}-win-x64.zip"
)
noextract=(
  "pnpm-${_pnpm}.tgz"
  "dotnet-runtime-${_dotnet6}-win-x64.zip"
  "dotnet-runtime-${_dotnet8}-win-x64.zip"
  "dotnet-runtime-${_dotnet10}-win-x64.zip"
  "windowsdesktop-runtime-${_dotnet6}-win-x64.zip"
  "windowsdesktop-runtime-${_dotnet8}-win-x64.zip"
  "windowsdesktop-runtime-${_dotnet10}-win-x64.zip"
)
sha512sums=(
  # Vortex is pinned by _upstream_commit.
  'SKIP'
  # pnpm is executed during the build, so keep its upstream archive verifiable.
  '0b7f8b98060031904c017e3a41eb187a16d40eeb829b95c4f8cb03681761fc4ab53dd219115b9b447f4dce1a05a214764461e7d3703392a9f32f9511ce8c86c8'
  # All following local files are versioned together with this PKGBUILD, so
  # hashing them only duplicates Git integrity.
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  'SKIP'
  # Keep integrity checks for binaries downloaded outside this repository.
  '935db5c6cee19f2c016e67168bfae7b491044735de76c673abb3b125dd325fd5e779d7efe12ba80178d46689ae70a25e558a3fa846417d44c5f4ca256e7f4bf2'
  'e3f31d298a2b674b54c7fc89fb3f06d9645fc5879a54f2ebf2ea20e9ee7ae55f1bfe3284c1f90a591d6be2d6bcd251790ddc27771d65303e7a6a56d331df4632'
  '2161dfa1cf027cdc074de7195b5f206b17ebd829ae415b9e7c9ee5f06d3952b6583030022dbe0d6e9221b5c577c411d7cd5322241f6d2299d9c886641215699b'
  'cee88fef07643dceb3d34ea71b64eeae85b8e39e7042bc4d35bc3a1f1df29373681dc48e31c01c9f593ec412699f6762b6fc5817433283c89df35a27ce8885bf'
  '7cf8d7ec8daeb2734dc44e0a06ca5001cdb459ba7534f4821b6a0e918cf4004e45531d5df794885b0a48ffb61658fc4a43ff23a3260fe9bbc1c32f807d422651'
  '58e243f490e09b00ef8c20d7c3dc06d0385aa4180b359eeb4ae8924ad1300fd19ec96c10e3989a96c4ce0076cf38e639bfb2b909baace73864dac28d64cdf9fc'
)

prepare() {
  cd "$srcdir/vortex"

  _activate_upstream_pnpm

  local compatibility_patch
  for compatibility_patch in "${_patches[@]}"; do
    patch -Np1 -i "$srcdir/$compatibility_patch"
  done

  node - "$pkgver" "$pkgver-$pkgrel" <<'NODE'
const fs = require('node:fs');
for (const file of ['src/main/package.json', 'packages/vortex-api/package.json']) {
  const metadata = JSON.parse(fs.readFileSync(file, 'utf8'));
  metadata.version = process.argv[2];
  fs.writeFileSync(file, JSON.stringify(metadata, null, 2) + '\n');
}
fs.writeFileSync(
  'src/renderer/src/extensions/updater/linuxBuild.ts',
  `// Generated by the Linux PKGBUILD.\nexport const LINUX_PACKAGE_VERSION: string = ${JSON.stringify(process.argv[3])};\n`,
);
NODE

  export npm_config_runtime='electron'
  export npm_config_target='44.2.0'
  export npm_config_disturl='https://electronjs.org/headers'
  # pnpm builds native addons in parallel, and each node-gyp process would
  # otherwise download and extract the Electron headers into the same cache
  # directory at once, letting some read a partially written common.gypi.
  node-gyp install
  pnpm install --frozen-lockfile
  pnpm --filter @vortex/main exec electron-rebuild \
    --force --version "$npm_config_target" \
    --module-dir "$srcdir/vortex/extensions/theme-switcher" \
    --types prod,dev,optional --only font-scanner
}

build() {
  cd "$srcdir/vortex"

  _activate_upstream_pnpm

  export CI=1
  export NODE_ENV='production'
  export NO_PARALLEL=1
  export VORTEX_SKIP_SUBMODULES=1
  export npm_config_runtime='electron'
  export npm_config_target='44.2.0'
  export npm_config_disturl='https://electronjs.org/headers'

  pnpm run build

  local gamebryo_plugin
  for gamebryo_plugin in gamebryo-archive-support gamebryo-savegame-management; do
    if [[ ! -s "$srcdir/vortex/extensions/$gamebryo_plugin/dist/index.cjs" ]]; then
      printf 'Gamebryo extension was not built for Linux: %s\n' "$gamebryo_plugin" >&2
      return 1
    fi
  done
  if [[ -n "$(
    find "$srcdir/vortex/extensions/gamebryo-archive-support/dist" \
      -type f -name '*.node' -print -quit
  )" ]]; then
    printf 'Gamebryo archive support unexpectedly contains a native Node addon\n' >&2
    return 1
  fi

  pnpm nx run @vortex/main:publish

  # leveldown 5.6.0 ships an old N-API prebuild that can segfault
  # under modern Electron / Node in snappy::CompressFragment while Vortex updates its
  # metadata database, causing Electron to restart the renderer indefinitely.
  # Use the rebuilt addon in both lookup locations.
  local leveldown_dir="$srcdir/vortex/src/main/dist/node_modules/leveldown"
  local leveldown_build="$leveldown_dir/build/Release/leveldown.node"
  local leveldown_prebuild="$leveldown_dir/prebuilds/linux-x64/node.napi.glibc.node"
  # Old LevelDB/Snappy code miscompiles with aggressive local ISA flags such
  # as -march=native on some toolchains and then crashes while compressing the
  # state database. Rebuild this addon for the portable x86-64 baseline even
  # when the host makepkg.conf requests x86-64-v3 or newer instructions.
  local leveldown_cflags='-march=x86-64 -mtune=generic -O2 -pipe -fno-plt -fexceptions -Wp,-D_FORTIFY_SOURCE=3 -Wformat -Werror=format-security -fstack-clash-protection -fcf-protection'
  (
    cd "$leveldown_dir"
    CFLAGS="$leveldown_cflags" \
      CXXFLAGS="$leveldown_cflags -Wp,-D_GLIBCXX_ASSERTIONS" \
      npm_config_runtime='electron' \
      npm_config_target='44.2.0' \
      npm_config_disturl='https://electronjs.org/headers' \
      "$srcdir/vortex/src/main/dist/node_modules/.bin/node-gyp" rebuild
  )
  if [[ ! -f "$leveldown_build" || ! -f "$leveldown_prebuild" ]]; then
    printf 'The rebuilt or prebuilt leveldown addon is missing\n' >&2
    return 1
  fi
  local leveldown_isa
  leveldown_isa="$(
    readelf --notes "$leveldown_build" \
      | sed -n 's/^[[:space:]]*x86 ISA used: //p'
  )"
  if [[ "$leveldown_isa" != 'x86-64-baseline' ]]; then
    printf 'The rebuilt leveldown addon is not portable x86-64\n' >&2
    return 1
  fi
  install -Dm755 "$leveldown_build" "$leveldown_prebuild"
  if ! cmp -s "$leveldown_build" "$leveldown_prebuild"; then
    printf 'Unable to replace the incompatible leveldown prebuild\n' >&2
    return 1
  fi

  # Some Nx targets stage Electron output as part of their dependency graph.
  # Always package into a fresh, explicitly scoped directory.
  rm -rf "$srcdir/vortex/dist/linux-unpacked"
  cd src/main/dist
  ./node_modules/.bin/electron-builder \
    --config ./electron-builder.config.json \
    --publish never \
    --linux dir \
    --x64 \
    -c.compression=store

  # copy-assets skips LOOT silently when node-loot failed to build.
  local loot_release="$srcdir/vortex/dist/linux-unpacked/resources/app.asar.unpacked/assets/loot/build/Release"
  if [[ ! -f "$loot_release/node-loot.node" || ! -f "$loot_release/libloot.so.0" ]]; then
    printf 'LOOT is missing from the packaged app\n' >&2
    return 1
  fi
  if ldd "$loot_release/node-loot.node" | grep -Fq 'not found'; then
    printf 'LOOT has unresolved libraries\n' >&2
    return 1
  fi
}

package() {
  cd "$srcdir/vortex"

  install -dm755 "$pkgdir/opt/Vortex"
  cp -a dist/linux-unpacked/. "$pkgdir/opt/Vortex/"

  # The native FOMOD addon is built with an absolute RUNPATH pointing at the
  # build tree. Make the packaged addon relocatable so it can find the
  # co-located NativeAOT library after installation and inside an AppImage.
  local fomod_release_dir="$pkgdir/opt/Vortex/resources/app.asar.unpacked/node_modules/@nexusmods/fomod-installer-native/build/Release"
  local fomod_node="$fomod_release_dir/modinstaller.node"
  local fomod_library="$fomod_release_dir/ModInstaller.Native.so"
  if [[ ! -f "$fomod_node" || ! -f "$fomod_library" ]]; then
    printf 'Native FOMOD runtime files are missing from the Electron output\n' >&2
    return 1
  fi
  patchelf --set-rpath '$ORIGIN' "$fomod_node"
  if [[ "$(patchelf --print-rpath "$fomod_node")" != '$ORIGIN' ]]; then
    printf 'Unable to make the native FOMOD addon relocatable\n' >&2
    return 1
  fi

  install -dm755 "$pkgdir/opt/Vortex/dotnet-win-x64"
  local runtime_version
  for runtime_version in "$_dotnet6" "$_dotnet8" "$_dotnet10"; do
    bsdtar -xf "$srcdir/dotnet-runtime-${runtime_version}-win-x64.zip" \
      -C "$pkgdir/opt/Vortex/dotnet-win-x64"
    bsdtar -xf "$srcdir/windowsdesktop-runtime-${runtime_version}-win-x64.zip" \
      -C "$pkgdir/opt/Vortex/dotnet-win-x64"
  done

  chmod 4755 "$pkgdir/opt/Vortex/chrome-sandbox"

  install -Dm755 "$srcdir/vortex.sh" "$pkgdir/usr/bin/vortex"
  install -Dm644 "$srcdir/vortex.desktop" \
    "$pkgdir/usr/share/applications/com.nexusmods.vortex.desktop"
  install -Dm644 assets/images/vortex.png \
    "$pkgdir/usr/share/icons/hicolor/256x256/apps/vortex.png"
  install -Dm644 src/renderer/node_modules/loot/LICENSE.md \
    "$pkgdir/usr/share/licenses/$pkgname/LOOT-LICENSE.md"
  install -Dm644 LICENSE.md "$pkgdir/usr/share/licenses/$pkgname/VORTEX-LICENSE.md"
  install -Dm644 "$srcdir/LICENSE" \
    "$pkgdir/usr/share/licenses/$pkgname/PATCHES-GPL-3.0.txt"
  install -Dm644 "$srcdir/README.md" \
    "$pkgdir/usr/share/doc/$pkgname/README.md"
}
