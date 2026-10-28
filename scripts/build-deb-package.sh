#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly PACKAGE_PATH="${1:?usage: build-deb-package.sh PACKAGE [OUTPUT_DIRECTORY]}"
readonly OUTPUT_DIRECTORY="${2:-${REPOSITORY_ROOT}/dist}"
readonly METAINFO_NAME='com.nexusmods.vortex.metainfo.xml'
# shellcheck source=scripts/dotnet-runtime.sh
source "$REPOSITORY_ROOT/scripts/dotnet-runtime.sh"

# Package names as Ubuntu 24.04 and Debian 13 ship them. The libc6 and
# libstdc++6 versions are added from the binaries below. .NET loads whichever
# ICU it finds, so any of these will do.
readonly DEB_DEPENDS=(
  'libasound2t64'
  'libatk-bridge2.0-0t64'
  'libatk1.0-0t64'
  'libatspi2.0-0t64'
  'libcairo2'
  'libcups2t64'
  'libdbus-1-3'
  'libdrm2'
  'libexpat1'
  'libfontconfig1'
  'libgbm1'
  'libglib2.0-0t64'
  'libglib2.0-bin'
  'libgtk-3-0t64'
  'libicu74 | libicu75 | libicu76 | libicu77 | libicu78 | libicu79 | libicu80'
  'libnotify4'
  'libnspr4'
  'libnss3'
  'libpango-1.0-0'
  'libsecret-1-0'
  'libudev1'
  'libx11-6'
  'libxcb1'
  'libxcomposite1'
  'libxdamage1'
  'libxext6'
  'libxfixes3'
  'libxkbcommon0'
  'libxrandr2'
  'libxss1'
  'wine | wine64 | winehq-stable | winehq-staging | winehq-devel'
  'xdg-utils'
)
readonly DEB_RECOMMENDS=(
  'libayatana-appindicator3-1 | libappindicator3-1'
)
readonly DEB_SUGGESTS=(
  'kde-cli-tools'
  'pipewire'
)

for command_name in bsdtar curl dpkg-deb file install objdump sha256sum sha512sum; do
  if ! command -v "$command_name" >/dev/null; then
    printf 'Required build command is missing: %s\n' "$command_name" >&2
    exit 2
  fi
done

if [[ ! -f "$PACKAGE_PATH" ]]; then
  printf 'Arch package was not found: %s\n' "$PACKAGE_PATH" >&2
  exit 2
fi

package_info="$(bsdtar -xOf "$PACKAGE_PATH" .PKGINFO)"
package_name="$(sed -n 's/^pkgname = //p' <<< "$package_info")"
package_revision="$(sed -n 's/^pkgver = //p' <<< "$package_info")"
package_arch="$(sed -n 's/^arch = //p' <<< "$package_info")"
package_description="$(sed -n 's/^pkgdesc = //p' <<< "$package_info")"
package_url="$(sed -n 's/^url = //p' <<< "$package_info")"
release_version="$(sed -n 's/^\tpkgver = //p' "$REPOSITORY_ROOT/.SRCINFO" | head -n 1)"
maintainer="$(sed -n 's/^# Maintainer: //p' "$REPOSITORY_ROOT/PKGBUILD")"

if [[ "$package_name" != vortex-linux || -z "$package_revision" || \
    -z "$release_version" || "$package_revision" != "${release_version}-"* || \
    "$package_arch" != x86_64 || -z "$package_description" || \
    -z "$package_url" || -z "$maintainer" ]]; then
  printf 'Unsupported package metadata: %s %s %s\n' \
    "$package_name" "$package_revision" "$package_arch" >&2
  exit 2
fi
release_date="$(date -u +%Y-%m-%d)"

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/vortex-deb.XXXXXX")"
cleanup() {
  rm -rf -- "$work_directory"
}
trap cleanup EXIT

package_root="$work_directory/root"
doc_directory="$package_root/usr/share/doc/$package_name"
install -dm755 "$package_root"

bsdtar -xf "$PACKAGE_PATH" -C "$package_root" \
  opt/Vortex \
  usr/share/applications/com.nexusmods.vortex.desktop \
  usr/share/icons/hicolor/256x256/apps/vortex.png \
  usr/share/licenses/vortex-linux \
  usr/share/doc/vortex-linux

# Electron falls back to this helper where unprivileged user namespaces are
# restricted, as on Ubuntu 24.04. bsdtar drops the setuid bit for normal users.
chmod 4755 "$package_root/opt/Vortex/chrome-sandbox"

install_dotnet_runtime "$package_root/opt/Vortex/dotnet-linux-x64" \
  "$work_directory/dotnet-runtime-linux-x64.tar.gz"
install -Dm755 "$REPOSITORY_ROOT/vortex.sh" "$package_root/usr/bin/vortex"

# Debian keeps licenses next to the documentation and expects a copyright file.
mv "$package_root/usr/share/licenses/vortex-linux"/* "$doc_directory/"
rm -r "$package_root/usr/share/licenses"
cat > "$doc_directory/copyright" <<EOF
Vortex for Linux: ${package_url}

Vortex is published by Nexus Mods at https://github.com/Nexus-Mods/Vortex
under the GNU General Public License, version 3 (VORTEX-LICENSE.md). The
Linux patches and packaging are GPL-3.0-only (PATCHES-GPL-3.0.txt). LOOT's
license is in LOOT-LICENSE.md, Electron's and Chromium's are in
/opt/Vortex/LICENSE.electron.txt and /opt/Vortex/LICENSES.chromium.html.
EOF

metainfo_path="$package_root/usr/share/metainfo/$METAINFO_NAME"
install -dm755 "$(dirname "$metainfo_path")"
sed \
  -e "s/@PACKAGE_REVISION@/${package_revision}/g" \
  -e "s/@RELEASE_DATE@/${release_date}/g" \
  "$REPOSITORY_ROOT/appimage/$METAINFO_NAME" > "$metainfo_path"
if grep -q '@[A-Z_]*@' "$metainfo_path"; then
  printf 'The AppStream metadata still contains placeholders\n' >&2
  exit 1
fi
if command -v appstreamcli >/dev/null; then
  appstreamcli validate --no-net "$metainfo_path"
else
  printf 'appstreamcli is not installed; skipping AppStream validation\n' >&2
fi

# The newest glibc and libstdc++ symbols the binaries use decide which
# distributions can run them. Declaring them lets apt refuse an older system
# instead of Vortex failing at startup. libstdc++6 carries the GCC version.
elf_files="$work_directory/elf-files"
find "$package_root" -type f -print0 \
  | xargs -0 file --no-pad --separator '|' \
  | sed -n 's/| ELF 64-bit .*//p' > "$elf_files"
symbol_versions="$(
  while IFS= read -r elf_file; do
    # Static executables such as 7zzs have no dynamic symbols.
    objdump -T "$elf_file" 2>/dev/null || true
  done < "$elf_files" | grep -oE '(GLIBC_2|GLIBCXX_3\.4)\.[0-9]+' | sort -uV
)"
glibc_minimum="$(grep '^GLIBC_' <<< "$symbol_versions" | tail -n 1 | sed 's/^GLIBC_//' || true)"
glibcxx_minimum="$(grep '^GLIBCXX_' <<< "$symbol_versions" | tail -n 1 || true)"
case "$glibcxx_minimum" in
  ''|GLIBCXX_3.4.[0-9]|GLIBCXX_3.4.1[0-9]|GLIBCXX_3.4.2[0-9]) libstdcxx_minimum='' ;;
  GLIBCXX_3.4.30) libstdcxx_minimum='12' ;;
  GLIBCXX_3.4.31) libstdcxx_minimum='13' ;;
  GLIBCXX_3.4.32) libstdcxx_minimum='13.2' ;;
  GLIBCXX_3.4.33) libstdcxx_minimum='14' ;;
  GLIBCXX_3.4.34) libstdcxx_minimum='15' ;;
  *)
    printf 'Unknown libstdc++ symbol version %s; add its GCC release here\n' \
      "$glibcxx_minimum" >&2
    exit 1
    ;;
esac
if [[ ! "$glibc_minimum" =~ ^2\.[0-9]+$ ]]; then
  printf 'Unable to determine the glibc version the binaries need\n' >&2
  exit 1
fi

depends=("libc6 (>= ${glibc_minimum})")
if [[ -n "$libstdcxx_minimum" ]]; then
  depends+=("libstdc++6 (>= ${libstdcxx_minimum})")
fi
depends+=("${DEB_DEPENDS[@]}")
join_fields() {
  local IFS=,
  sed 's/,/, /g' <<< "$*"
}

installed_size="$(du -sk --apparent-size "$package_root" | cut -f1)"
install -dm755 "$package_root/DEBIAN"
cat > "$package_root/DEBIAN/control" <<EOF
Package: ${package_name}
Version: ${package_revision}
Architecture: amd64
Maintainer: ${maintainer}
Installed-Size: ${installed_size}
Depends: $(join_fields "${depends[@]}")
Recommends: $(join_fields "${DEB_RECOMMENDS[@]}")
Suggests: $(join_fields "${DEB_SUGGESTS[@]}")
Section: games
Priority: optional
Homepage: ${package_url}
Description: ${package_description}
 Vortex is the mod manager from Nexus Mods. This build patches it to run
 natively on Linux: it deploys mods into the game's Proton or Wine prefix and
 launches games through Steam, Heroic, Lutris or Bottles.
 .
 Not affiliated with or supported by Nexus Mods.
EOF
cat > "$package_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = configure ]; then
  echo "To select Vortex for Nexus links, run:"
  echo "  xdg-mime default com.nexusmods.vortex.desktop x-scheme-handler/nxm"
fi
EOF
chmod 755 "$package_root/DEBIAN/postinst"

install -dm755 "$OUTPUT_DIRECTORY"
deb_archive="${package_name}_${release_version}_amd64.deb"
dpkg-deb --root-owner-group -Zxz --build "$package_root" "$OUTPUT_DIRECTORY/$deb_archive"

sandbox_entry="$(dpkg-deb --contents "$OUTPUT_DIRECTORY/$deb_archive" \
  | grep -E ' \./opt/Vortex/chrome-sandbox$')"
if [[ "$sandbox_entry" != '-rwsr-xr-x root/root '* ]]; then
  printf 'chrome-sandbox is not setuid root in the package: %s\n' "$sandbox_entry" >&2
  exit 1
fi

(
  cd "$OUTPUT_DIRECTORY"
  sha256sum "$deb_archive" > "${deb_archive}.sha256"
  sha256sum --check "${deb_archive}.sha256"
)

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'deb_archive=%s\n' "$deb_archive" >> "$GITHUB_OUTPUT"
  printf 'deb_checksum=%s.sha256\n' "$deb_archive" >> "$GITHUB_OUTPUT"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
### Debian package

- Archive: \`${deb_archive}\`
- Version: \`${package_revision}\`
- Size: \`$(du -h "$OUTPUT_DIRECTORY/$deb_archive" | cut -f1)\`
- Needs: \`libc6 (>= ${glibc_minimum})\`${libstdcxx_minimum:+, \`libstdc++6 (>= ${libstdcxx_minimum})\`}
- Bundled Linux .NET runtime: \`${DOTNET_RUNTIME_VERSION}\`
EOF
fi

printf 'Built Debian package: %s\n' "$OUTPUT_DIRECTORY/$deb_archive"
