#!/usr/bin/env bash

set -Eeuo pipefail
umask 022

REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly PACKAGE_PATH="${1:?usage: build-distro-packages.sh PACKAGE [OUTPUT_DIRECTORY]}"
readonly OUTPUT_DIRECTORY="${2:-${REPOSITORY_ROOT}/dist}"
# shellcheck source=scripts/package-common.sh
source "$REPOSITORY_ROOT/scripts/package-common.sh"

# .NET loads whichever ICU it finds.
readonly ICU_VERSIONS=(74 75 76 77 78 79 80)
deb_icu="$(printf 'libicu%s | ' "${ICU_VERSIONS[@]}")"
rpm_icu="$(printf 'libicuuc.so.%s()(64bit) or ' "${ICU_VERSIONS[@]}")"

# Package names as Ubuntu 24.04 and Debian 13 ship them. The libc6 and
# libstdc++6 versions are added from the binaries below.
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
  "${deb_icu% | }"
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

# rpmbuild adds the libraries the binaries link, with the glibc and libstdc++
# symbol versions they need, so these are only what Vortex loads at runtime.
# Library names and paths work the same on Fedora and openSUSE.
readonly RPM_REQUIRES=(
  '(wine or winehq-stable or winehq-staging or winehq-devel)'
  'xdg-utils'
  '/usr/bin/gio'
  'libnotify.so.4()(64bit)'
  'libsecret-1.so.0()(64bit)'
  "(${rpm_icu% or })"
  # The interface stays blank without any font, and a minimal openSUSE has
  # none. Debian's fontconfig already pulls one in.
  'liberation-fonts'
)
readonly RPM_RECOMMENDS=(
  'libayatana-appindicator3.so.1()(64bit)'
)

readonly DESCRIPTION='Vortex is the mod manager from Nexus Mods. This build patches it to run
natively on Linux: it deploys mods into the game'"'"'s Proton or Wine prefix and
launches games through Steam, Heroic, Lutris or Bottles.

Not affiliated with or supported by Nexus Mods.'

for command_name in bsdtar cp curl dpkg-deb file install objdump rpm rpmbuild sha256sum sha512sum; do
  if ! command -v "$command_name" >/dev/null; then
    printf 'Required build command is missing: %s\n' "$command_name" >&2
    exit 2
  fi
done

read_package_metadata "$PACKAGE_PATH"
package_release="${package_revision#"${release_version}-"}"
maintainer="$(sed -n 's/^# Maintainer: //p' "$REPOSITORY_ROOT/PKGBUILD")"
if [[ -z "$maintainer" ]]; then
  printf 'PKGBUILD names no maintainer\n' >&2
  exit 2
fi

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/vortex-distro.XXXXXX")"
cleanup() {
  rm -rf -- "$work_directory"
}
trap cleanup EXIT

# Both packages are hard-linked copies of one staged tree, in the layout RPM
# distributions use.
stage="$work_directory/stage"
install -dm755 "$stage"
bsdtar -xf "$PACKAGE_PATH" -C "$stage" \
  opt/Vortex \
  usr/share/applications/com.nexusmods.vortex.desktop \
  usr/share/icons/hicolor/256x256/apps/vortex.png \
  usr/share/licenses/vortex-linux \
  usr/share/doc/vortex-linux

# Electron falls back to this helper where unprivileged user namespaces are
# restricted, as on Ubuntu 24.04. bsdtar drops the setuid bit for normal users.
chmod 4755 "$stage/opt/Vortex/chrome-sandbox"

install_dotnet_runtime "$stage/opt/Vortex/dotnet-linux-x64" \
  "$work_directory/dotnet-runtime-linux-x64.tar.gz"
install -Dm755 "$REPOSITORY_ROOT/vortex.sh" "$stage/usr/bin/vortex"

install_metainfo "$stage/usr/share/metainfo/$METAINFO_NAME"

install -dm755 "$OUTPUT_DIRECTORY"

### Debian package

# The newest glibc and libstdc++ symbols the binaries use decide which
# distributions can run them. Declaring them lets apt refuse an older system
# instead of Vortex failing at startup. libstdc++6 carries the GCC version.
elf_files="$work_directory/elf-files"
find "$stage" -type f -print0 \
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

deb_root="$work_directory/deb"
cp -al "$stage" "$deb_root"

# Debian keeps licenses next to the documentation and expects a copyright file.
doc_directory="$deb_root/usr/share/doc/$package_name"
mv "$deb_root/usr/share/licenses/vortex-linux"/* "$doc_directory/"
rm -r "$deb_root/usr/share/licenses"
cat > "$doc_directory/copyright" <<EOF
Vortex for Linux: ${package_url}

Vortex is published by Nexus Mods at https://github.com/Nexus-Mods/Vortex
under the GNU General Public License, version 3 (VORTEX-LICENSE.md). The
Linux patches and packaging are GPL-3.0-only (PATCHES-GPL-3.0.txt). LOOT's
license is in LOOT-LICENSE.md, Electron's and Chromium's are in
/opt/Vortex/LICENSE.electron.txt and /opt/Vortex/LICENSES.chromium.html.
EOF

installed_size="$(du -sk --apparent-size "$deb_root" | cut -f1)"
install -dm755 "$deb_root/DEBIAN"
cat > "$deb_root/DEBIAN/control" <<EOF
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
$(sed -e 's/^$/./' -e 's/^/ /' <<< "$DESCRIPTION")
EOF
cat > "$deb_root/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e

if [ "$1" = configure ]; then
  echo "To select Vortex for Nexus links, run:"
  echo "  xdg-mime default com.nexusmods.vortex.desktop x-scheme-handler/nxm"
fi
EOF
chmod 755 "$deb_root/DEBIAN/postinst"

deb_archive="${package_name}_${release_version}_amd64.deb"
dpkg-deb --root-owner-group -Zxz --build "$deb_root" "$OUTPUT_DIRECTORY/$deb_archive"
rm -rf -- "$deb_root"

sandbox_entry="$(dpkg-deb --contents "$OUTPUT_DIRECTORY/$deb_archive" \
  | grep -E ' \./opt/Vortex/chrome-sandbox$')"
if [[ "$sandbox_entry" != '-rwsr-xr-x root/root '* ]]; then
  printf 'chrome-sandbox is not setuid root in the Debian package: %s\n' \
    "$sandbox_entry" >&2
  exit 1
fi

### RPM package

# Requirements that libraries inside /opt/Vortex satisfy are dropped, and so
# is LTTng, which only the optional .NET tracing provider links. Nothing in
# /opt/Vortex is offered to other packages.
bundled_libraries="$(
  find "$stage/opt/Vortex" -type f -regextype posix-extended \
    -regex '.*\.so(\.[0-9]+)*' -printf '%f\n' \
    | sort -u | sed 's/[.]/[.]/g' | paste -sd '|'
)"
rpm_topdir="$work_directory/rpm"
install -dm755 "$rpm_topdir"
cat > "$rpm_topdir/${package_name}.spec" <<EOF
# Generated by build-distro-packages.sh from the Arch package.
%global debug_package %{nil}
# Electron and the native addons ship as built, without stripping.
%global __os_install_post %{nil}
# Build ID links would clash with other packages bundling the same Electron.
%global _build_id_links none
# openSUSE's rpm 4.20 can't read the v6 format rpm 6 writes by default.
%global _rpmformat 4
%global _binary_payload w7T0.zstdio
%global __provides_exclude_from ^/opt/Vortex/
%global __requires_exclude ^(${bundled_libraries}|liblttng-ust[.]so[.][0-9]+)[(]

Name: ${package_name}
Version: ${release_version}
Release: ${package_release}
Summary: ${package_description}
License: ${package_license}
URL: ${package_url}
ExclusiveArch: x86_64
$(printf 'Requires: %s\n' "${RPM_REQUIRES[@]}")
$(printf 'Recommends: %s\n' "${RPM_RECOMMENDS[@]}")

%description
${DESCRIPTION}

%install
cp -al '${stage}/.' '%{buildroot}/'

%post
if [ "\$1" -eq 1 ]; then
  echo "To select Vortex for Nexus links, run:"
  echo "  xdg-mime default com.nexusmods.vortex.desktop x-scheme-handler/nxm"
fi

%files
%defattr(-,root,root,-)
/opt/Vortex
/usr/bin/vortex
/usr/share/applications/com.nexusmods.vortex.desktop
/usr/share/icons/hicolor/256x256/apps/vortex.png
/usr/share/metainfo/${METAINFO_NAME}
%license /usr/share/licenses/${package_name}
%doc /usr/share/doc/${package_name}
EOF

rpmbuild -bb --target x86_64 \
  --define "_topdir $rpm_topdir" \
  "$rpm_topdir/${package_name}.spec"
mapfile -t built_rpms < <(find "$rpm_topdir/RPMS" -type f -name '*.rpm')
if ((${#built_rpms[@]} != 1)); then
  printf 'Expected one RPM package, got %d\n' "${#built_rpms[@]}" >&2
  exit 1
fi
rpm_archive="${package_name}-${release_version}-x86_64.rpm"
install -m644 "${built_rpms[0]}" "$OUTPUT_DIRECTORY/$rpm_archive"
rm -rf -- "$rpm_topdir"

sandbox_entry="$(rpm -qp --qf '[%{FILEMODES:perms} %{FILEUSERNAME}:%{FILEGROUPNAME} %{FILENAMES}\n]' \
  "$OUTPUT_DIRECTORY/$rpm_archive" | grep -E ' /opt/Vortex/chrome-sandbox$')"
if [[ "$sandbox_entry" != '-rwsr-xr-x root:root '* ]]; then
  printf 'chrome-sandbox is not setuid root in the RPM package: %s\n' \
    "$sandbox_entry" >&2
  exit 1
fi
rpm_requires="$(rpm -qp --requires "$OUTPUT_DIRECTORY/$rpm_archive")"
if ! grep -q '^libc\.so\.6(GLIBC_2\.[0-9]*)(64bit)$' <<< "$rpm_requires"; then
  printf 'rpmbuild did not record the glibc version the binaries need\n' >&2
  exit 1
fi
leaked_provides="$(rpm -qp --provides "$OUTPUT_DIRECTORY/$rpm_archive" | grep -F '.so' || true)"
if [[ -n "$leaked_provides" ]]; then
  printf 'The RPM package offers its bundled libraries to the system:\n%s\n' \
    "$leaked_provides" >&2
  exit 1
fi
rpm_glibc="$(grep -o '^libc\.so\.6(GLIBC_2\.[0-9]*)' <<< "$rpm_requires" | sort -V | tail -n 1)"

(
  cd "$OUTPUT_DIRECTORY"
  sha256sum "$deb_archive" > "${deb_archive}.sha256"
  sha256sum "$rpm_archive" > "${rpm_archive}.sha256"
  sha256sum --check "${deb_archive}.sha256" "${rpm_archive}.sha256"
)

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'deb_archive=%s\n' "$deb_archive" >> "$GITHUB_OUTPUT"
  printf 'deb_checksum=%s.sha256\n' "$deb_archive" >> "$GITHUB_OUTPUT"
  printf 'rpm_archive=%s\n' "$rpm_archive" >> "$GITHUB_OUTPUT"
  printf 'rpm_checksum=%s.sha256\n' "$rpm_archive" >> "$GITHUB_OUTPUT"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
### Debian and RPM packages

- Debian: \`${deb_archive}\`, \`$(du -h "$OUTPUT_DIRECTORY/$deb_archive" | cut -f1)\`, needs \`libc6 (>= ${glibc_minimum})\`${libstdcxx_minimum:+ and \`libstdc++6 (>= ${libstdcxx_minimum})\`}
- RPM: \`${rpm_archive}\`, \`$(du -h "$OUTPUT_DIRECTORY/$rpm_archive" | cut -f1)\`, needs \`${rpm_glibc}\`
- Version: \`${package_revision}\`
- Bundled Linux .NET runtime: \`${DOTNET_RUNTIME_VERSION}\`
EOF
fi

printf 'Built Debian package: %s\n' "$OUTPUT_DIRECTORY/$deb_archive"
printf 'Built RPM package: %s\n' "$OUTPUT_DIRECTORY/$rpm_archive"
