#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
build_directory="${1:-${REPOSITORY_ROOT}/dist/arch-build}"
install -dm755 "$build_directory"
build_directory="$(cd -- "$build_directory" && pwd)"
if [[ "$build_directory" == "$REPOSITORY_ROOT" ]]; then
  printf 'Use a separate build directory, such as dist/arch-build\n' >&2
  exit 2
fi

for file in PKGBUILD .SRCINFO vortex.install vortex.sh vortex.desktop README.md LICENSE; do
  install -m644 "$REPOSITORY_ROOT/$file" "$build_directory/$file"
done
for patch in "$REPOSITORY_ROOT"/patches/[0-9][0-9][0-9][0-9]-*.patch; do
  install -m644 "$patch" "$build_directory/$(basename -- "$patch")"
done

printf 'Prepared Arch build directory: %s\n' "$build_directory"
