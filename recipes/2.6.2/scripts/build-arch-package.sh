#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIRECTORY="${1:-${REPOSITORY_ROOT}/dist}"
readonly BUILD_DIRECTORY="${REPOSITORY_ROOT}/dist/arch-build"

if ((EUID == 0)); then
  printf 'makepkg must run as an unprivileged build user\n' >&2
  exit 2
fi

for command_name in makepkg pacman sha256sum; do
  if ! command -v "$command_name" >/dev/null; then
    printf 'Required build command is missing: %s\n' "$command_name" >&2
    exit 2
  fi
done

cd "$REPOSITORY_ROOT"

generated_srcinfo="$(mktemp)"
cleanup() {
  rm -f -- "$generated_srcinfo"
}
trap cleanup EXIT

makepkg --printsrcinfo > "$generated_srcinfo"
if ! cmp --silent .SRCINFO "$generated_srcinfo"; then
  printf '.SRCINFO is out of sync with PKGBUILD\n' >&2
  diff --unified .SRCINFO "$generated_srcinfo" || true
  exit 1
fi

install -dm755 "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY="$(cd -- "$OUTPUT_DIRECTORY" && pwd)"
readonly OUTPUT_DIRECTORY
"$REPOSITORY_ROOT/scripts/prepare-arch-build.sh" "$BUILD_DIRECTORY"
cd "$BUILD_DIRECTORY"

mapfile -t expected_packages < <(makepkg --packagelist)
if ((${#expected_packages[@]} != 1)); then
  printf 'Expected one package archive, got %d\n' "${#expected_packages[@]}" >&2
  printf '  %s\n' "${expected_packages[@]}" >&2
  exit 1
fi

makepkg --cleanbuild --clean --noconfirm --nocheck

package_path="${expected_packages[0]}"
if [[ ! -f "$package_path" ]]; then
  printf 'Expected package was not created: %s\n' "$package_path" >&2
  exit 1
fi

read -r package_name package_version < <(pacman -Qp "$package_path")
if [[ "$package_name" != "vortex-linux" || -z "$package_version" ]]; then
  printf 'Unexpected package metadata: %s %s\n' "$package_name" "$package_version" >&2
  exit 1
fi

# pkgrel is required inside the Arch package so pacman can distinguish rebuilt
# packages. Keep it out of the public download name: users only need the Vortex
# version, while replacing a release should replace the file at the same name.
release_version="$(sed -n 's/^\tpkgver = //p' "$generated_srcinfo" | head -n 1)"
package_filename="$(basename -- "$package_path")"
versioned_prefix="${package_name}-${package_version}-x86_64"
if [[ -z "$release_version" || "$package_version" != "${release_version}-"* || \
    "$package_filename" != "${versioned_prefix}"* ]]; then
  printf 'Unable to derive the public package name from: %s\n' "$package_filename" >&2
  exit 1
fi
package_suffix="${package_filename#"$versioned_prefix"}"

install -dm755 "$OUTPUT_DIRECTORY"
package_archive="${package_name}-${release_version}-x86_64${package_suffix}"
install -m644 "$package_path" "$OUTPUT_DIRECTORY/$package_archive"
(
  cd "$OUTPUT_DIRECTORY"
  sha256sum "$package_archive" > "${package_archive}.sha256"
  sha256sum --check "${package_archive}.sha256"
)

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  printf 'package_name=%s\n' "$package_name" >> "$GITHUB_OUTPUT"
  printf 'package_version=%s\n' "$release_version" >> "$GITHUB_OUTPUT"
  printf 'package_revision=%s\n' "$package_version" >> "$GITHUB_OUTPUT"
  printf 'package_archive=%s\n' "$package_archive" >> "$GITHUB_OUTPUT"
  printf 'checksum_file=%s.sha256\n' "$package_archive" >> "$GITHUB_OUTPUT"
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" <<EOF
### Arch package

- Package: \`${package_name}\`
- Version: \`${release_version}\`
- Internal Arch revision: \`${package_version}\`
- Archive: \`${package_archive}\`
- Size: \`$(du -h "$OUTPUT_DIRECTORY/$package_archive" | cut -f1)\`
EOF
fi

printf 'Built %s %s: %s\n' \
  "$package_name" "$release_version" "$OUTPUT_DIRECTORY/$package_archive"
