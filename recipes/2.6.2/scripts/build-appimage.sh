#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly PACKAGE_PATH="${1:?usage: build-appimage.sh PACKAGE [OUTPUT_DIRECTORY]}"
readonly OUTPUT_DIRECTORY="${2:-${REPOSITORY_ROOT}/dist}"
readonly APPIMAGETOOL_URL='https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage'
readonly APPIMAGETOOL_SHA256='b90f4a8b18967545fda78a445b27680a1642f1ef9488ced28b65398f2be7add2'
readonly DOTNET_RUNTIME_VERSION='9.0.18'
readonly DOTNET_RUNTIME_URL="https://builds.dotnet.microsoft.com/dotnet/Runtime/${DOTNET_RUNTIME_VERSION}/dotnet-runtime-${DOTNET_RUNTIME_VERSION}-linux-x64.tar.gz"
readonly DOTNET_RUNTIME_SHA512='97eb89a5a3781b9761e2a850996912ae81b96996089c78abcebbc441113457088bfcbd7cf1fa97d3036f7ac8fe22c7d30e043e93ecafc910f07b73317c73bad5'

for command_name in bsdtar curl file install ldd patchelf sha256sum sha512sum; do
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
release_version="$(sed -n 's/^\tpkgver = //p' "$REPOSITORY_ROOT/.SRCINFO" | head -n 1)"

if [[ "$package_name" != vortex-linux || -z "$package_revision" || \
    -z "$release_version" || "$package_revision" != "${release_version}-"* || \
    "$package_arch" != x86_64 ]]; then
  printf 'Unsupported package metadata: %s %s %s\n' \
    "$package_name" "$package_revision" "$package_arch" >&2
  exit 2
fi

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

# Vortex's native dotnetprobe is a framework-dependent net9.0 executable. The
# Arch package gets a host runtime through pacman, but an AppImage must carry it
# itself so the startup check also works on a clean distribution.
curl --fail --location --silent --show-error \
  "$DOTNET_RUNTIME_URL" --output "$dotnet_runtime_path"
printf '%s  %s\n' "$DOTNET_RUNTIME_SHA512" "$dotnet_runtime_path" \
  | sha512sum --check --status
install -dm755 "$app_directory/usr/lib/dotnet"
bsdtar -xf "$dotnet_runtime_path" -C "$app_directory/usr/lib/dotnet"

if ! "$app_directory/usr/lib/dotnet/dotnet" --list-runtimes \
    | grep -Fqx "Microsoft.NETCore.App ${DOTNET_RUNTIME_VERSION} [$app_directory/usr/lib/dotnet/shared/Microsoft.NETCore.App]"; then
  printf 'The bundled .NET %s runtime is incomplete\n' "$DOTNET_RUNTIME_VERSION" >&2
  exit 1
fi

install -m755 "$REPOSITORY_ROOT/appimage/AppRun" "$app_directory/AppRun"
install -Dm644 "$REPOSITORY_ROOT/scripts/test-runtime.cjs" "$app_directory/usr/share/vortex-linux/test-runtime.cjs"
install -Dm644 "$REPOSITORY_ROOT/scripts/test-loot.cjs" "$app_directory/usr/share/vortex-linux/test-loot.cjs"
install -m644 \
  "$app_directory/usr/share/icons/hicolor/256x256/apps/vortex.png" \
  "$app_directory/vortex.png"
ln -s vortex.png "$app_directory/.DirIcon"

sed \
  -e 's/^Exec=.*/Exec=AppRun %u/' \
  -e 's/^X-AppImage-Version=.*/X-AppImage-Version='"$release_version"'/' \
  "$app_directory/usr/share/applications/com.nexusmods.vortex.desktop" \
  > "$app_directory/com.nexusmods.vortex.desktop"

if ! grep -q '^X-AppImage-Version=' "$app_directory/com.nexusmods.vortex.desktop"; then
  printf 'X-AppImage-Version=%s\n' "$release_version" \
    >> "$app_directory/com.nexusmods.vortex.desktop"
fi

curl --fail --location --silent --show-error \
  "$APPIMAGETOOL_URL" --output "$tool_path"
printf '%s  %s\n' "$APPIMAGETOOL_SHA256" "$tool_path" | sha256sum --check --status
chmod 755 "$tool_path"

install -dm755 "$OUTPUT_DIRECTORY"
appimage_archive="Vortex-${release_version}-x86_64.AppImage"
ARCH=x86_64 "$tool_path" --appimage-extract-and-run \
  "$app_directory" "$OUTPUT_DIRECTORY/$appimage_archive"
chmod 755 "$OUTPUT_DIRECTORY/$appimage_archive"

if [[ "$(file -b "$OUTPUT_DIRECTORY/$appimage_archive")" != *'ELF 64-bit'* ]]; then
  printf 'The generated AppImage is not an x86_64 ELF executable\n' >&2
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
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
### AppImage

- Archive: \`${appimage_archive}\`
- Size: \`$(du -h "$OUTPUT_DIRECTORY/$appimage_archive" | cut -f1)\`
- Bundled Linux .NET runtime: \`${DOTNET_RUNTIME_VERSION}\`
EOF
fi

printf 'Built AppImage: %s\n' "$OUTPUT_DIRECTORY/$appimage_archive"
