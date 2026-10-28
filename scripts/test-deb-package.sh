#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly PACKAGE_PATH="${1:?usage: test-deb-package.sh DEB [CONTAINER_IMAGE]}"
readonly CONTAINER_IMAGE="${2:-ubuntu:24.04}"

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is required to run the clean Debian package smoke test\n' >&2
  exit 2
fi

if [[ ! -f "$PACKAGE_PATH" ]]; then
  printf 'Debian package was not found: %s\n' "$PACKAGE_PATH" >&2
  exit 2
fi

ABSOLUTE_PACKAGE_PATH="$(cd -- "$(dirname -- "$PACKAGE_PATH")" && pwd)/$(basename -- "$PACKAGE_PATH")"
readonly ABSOLUTE_PACKAGE_PATH

printf 'Testing %s in a fresh %s container\n' \
  "$ABSOLUTE_PACKAGE_PATH" "$CONTAINER_IMAGE"
docker run --rm --platform linux/amd64 \
  --volume "$ABSOLUTE_PACKAGE_PATH:/artifact/vortex-linux.deb:ro" \
  --volume "$REPOSITORY_ROOT/scripts/test-deb-package-container.sh:/test-deb-package-container.sh:ro" \
  --volume "$REPOSITORY_ROOT/scripts/check-appimage-ui.py:/check-appimage-ui.py:ro" \
  --volume "$REPOSITORY_ROOT/scripts/test-runtime.cjs:/vortex-tests/test-runtime.cjs:ro" \
  --volume "$REPOSITORY_ROOT/scripts/test-loot.cjs:/vortex-tests/test-loot.cjs:ro" \
  "$CONTAINER_IMAGE" \
  bash /test-deb-package-container.sh /artifact/vortex-linux.deb
