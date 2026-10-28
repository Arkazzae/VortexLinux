#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly PACKAGE_PATH="${1:?usage: build-appimage.sh PACKAGE [OUTPUT_DIRECTORY]}"
readonly OUTPUT_DIRECTORY="${2:-${REPOSITORY_ROOT}/dist}"
readonly APPIMAGETOOL_URL='https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage'
readonly APPIMAGETOOL_SHA256='b90f4a8b18967545fda78a445b27680a1642f1ef9488ced28b65398f2be7add2'
# GitHub repository whose latest release AppImageUpdate-style tools (Gear Lever,
# AppImageLauncher, appimageupdatetool) check for a newer AppImage.
readonly RELEASE_REPOSITORY="${VORTEX_RELEASE_REPOSITORY:-${GITHUB_REPOSITORY:-Arkazzae/VortexLinux}}"
# shellcheck source=scripts/package-common.sh
source "$REPOSITORY_ROOT/scripts/package-common.sh"

for command_name in bsdtar curl file install ldd patchelf readelf sha256sum sha512sum; do
  if ! command -v "$command_name" >/dev/null; then
    printf 'Required build command is missing: %s\n' "$command_name" >&2
    exit 2
  fi
done

read_package_metadata "$PACKAGE_PATH"

if [[ ! "$RELEASE_REPOSITORY" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  printf 'Unsupported release repository: %s\n' "$RELEASE_REPOSITORY" >&2
  exit 2
fi
# https://github.com/AppImage/AppImageSpec/blob/master/draft.md#github-releases
update_information="gh-releases-zsync|${RELEASE_REPOSITORY%%/*}|${RELEASE_REPOSITORY#*/}|latest|Vortex-*-x86_64.AppImage.zsync"

work_directory="$(mktemp -d "${TMPDIR:-/tmp}/vortex-appimage.XXXXXX")"
cleanup() {
  rm -rf -- "$work_directory"
}
trap cleanup EXIT

app_directory="$work_directory/Vortex.AppDir"
tool_path="$work_directory/appimagetool-x86_64.AppImage"
dotnet_runtime_path="$work_directory/dotnet-runtime-linux-x64.tar.gz"
install -dm755 "$app_directory"

bsdtar -xf "$PACKAGE_PATH" -C "$app_directory" \
  opt/Vortex \
  usr/share/applications/com.nexusmods.vortex.desktop \
  usr/share/icons/hicolor/256x256/apps/vortex.png \
  usr/share/licenses/vortex-linux

packaged_version="$(env -u LD_LIBRARY_PATH ELECTRON_RUN_AS_NODE=1 \
  "$app_directory/opt/Vortex/vortex" -p 'require(process.argv[1]).version' \
  "$app_directory/opt/Vortex/resources/app.asar/package.json")"
if [[ "$packaged_version" != "$release_version" ]]; then
  printf 'Vortex reports version %s, but the package is %s\n' \
    "$packaged_version" "$release_version" >&2
  exit 1
fi

fomod_release_directory="$app_directory/opt/Vortex/resources/app.asar.unpacked/node_modules/@nexusmods/fomod-installer-native/build/Release"
fomod_node="$fomod_release_directory/modinstaller.node"
fomod_library="$fomod_release_directory/ModInstaller.Native.so"
if [[ ! -f "$fomod_node" || ! -f "$fomod_library" ]]; then
  printf 'The package is missing the native FOMOD runtime files\n' >&2
  exit 1
fi
if [[ "$(patchelf --print-rpath "$fomod_node")" != '$ORIGIN' ]]; then
  printf 'The native FOMOD addon is not relocatable\n' >&2
  exit 1
fi
fomod_dependencies="$(ldd "$fomod_node")"
if grep -Fq 'not found' <<< "$fomod_dependencies"; then
  printf 'The native FOMOD addon has unresolved dependencies:\n%s\n' \
    "$fomod_dependencies" >&2
  exit 1
fi

install_dotnet_runtime "$app_directory/usr/lib/dotnet" "$dotnet_runtime_path"

install -m755 "$REPOSITORY_ROOT/appimage/AppRun" "$app_directory/AppRun"
install -Dm644 "$REPOSITORY_ROOT/scripts/test-runtime.cjs" "$app_directory/usr/share/vortex-linux/test-runtime.cjs"
install -Dm644 "$REPOSITORY_ROOT/scripts/test-loot.cjs" "$app_directory/usr/share/vortex-linux/test-loot.cjs"
install -m644 \
  "$app_directory/usr/share/icons/hicolor/256x256/apps/vortex.png" \
  "$app_directory/vortex.png"
ln -s vortex.png "$app_directory/.DirIcon"

# The package revision tells AppImage managers apart from rebuilds of the same
# Vortex version.
sed \
  -e 's/^Exec=.*/Exec=AppRun %u/' \
  -e 's/^X-AppImage-Version=.*/X-AppImage-Version='"$package_revision"'/' \
  "$app_directory/usr/share/applications/com.nexusmods.vortex.desktop" \
  > "$app_directory/com.nexusmods.vortex.desktop"

if ! grep -q '^X-AppImage-Version=' "$app_directory/com.nexusmods.vortex.desktop"; then
  printf 'X-AppImage-Version=%s\n' "$package_revision" \
    >> "$app_directory/com.nexusmods.vortex.desktop"
fi

install_metainfo "$app_directory/usr/share/metainfo/$METAINFO_NAME"

curl --fail --location --silent --show-error \
  "$APPIMAGETOOL_URL" --output "$tool_path"
printf '%s  %s\n' "$APPIMAGETOOL_SHA256" "$tool_path" | sha256sum --check --status
chmod 755 "$tool_path"

install -dm755 "$OUTPUT_DIRECTORY"
appimage_archive="Vortex-${release_version}-x86_64.AppImage"
appimage_zsync="${appimage_archive}.zsync"
# appimagetool runs its bundled zsyncmake in the working directory, so build
# from the output directory to keep the .zsync next to the AppImage.
(
  cd "$OUTPUT_DIRECTORY"
  rm -f -- "$appimage_zsync"
  ARCH=x86_64 "$tool_path" --appimage-extract-and-run \
    --updateinformation "$update_information" \
    "$app_directory" "$appimage_archive"
)
chmod 755 "$OUTPUT_DIRECTORY/$appimage_archive"

if [[ "$(file -b "$OUTPUT_DIRECTORY/$appimage_archive")" != *'ELF 64-bit'* ]]; then
  printf 'The generated AppImage is not an x86_64 ELF executable\n' >&2
  exit 1
fi

if ! readelf --string-dump=.upd_info --wide "$OUTPUT_DIRECTORY/$appimage_archive" \
    | grep -Fq -- "$update_information"; then
  printf 'The generated AppImage does not embed the update information\n' >&2
  exit 1
fi
if [[ ! -s "$OUTPUT_DIRECTORY/$appimage_zsync" ]] || \
    ! grep -aFxq "URL: ${appimage_archive}" "$OUTPUT_DIRECTORY/$appimage_zsync"; then
  printf 'appimagetool did not generate %s for the AppImage\n' "$appimage_zsync" >&2
  exit 1
fi

(
  cd "$OUTPUT_DIRECTORY"
  sha256sum "$appimage_archive" > "${appimage_archive}.sha256"
  sha256sum --check "${appimage_archive}.sha256"
)

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'appimage_archive=%s\n' "$appimage_archive" >> "$GITHUB_OUTPUT"
  printf 'appimage_checksum=%s.sha256\n' "$appimage_archive" >> "$GITHUB_OUTPUT"
  printf 'appimage_zsync=%s\n' "$appimage_zsync" >> "$GITHUB_OUTPUT"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
### AppImage

- Archive: \`${appimage_archive}\`
- Size: \`$(du -h "$OUTPUT_DIRECTORY/$appimage_archive" | cut -f1)\`
- Bundled Linux .NET runtime: \`${DOTNET_RUNTIME_VERSION}\`
- Update information: \`${update_information}\`
- zsync: \`${appimage_zsync}\`
EOF
fi

printf 'Built AppImage: %s\n' "$OUTPUT_DIRECTORY/$appimage_archive"
