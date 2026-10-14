#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly APPIMAGE_PATH="${1:?usage: test-appimage.sh APPIMAGE [CONTAINER_IMAGE]}"
readonly CONTAINER_IMAGE="${2:-ubuntu:24.04}"

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is required to run the clean AppImage smoke test\n' >&2
  exit 2
fi

if [[ ! -f "$APPIMAGE_PATH" ]]; then
  printf 'AppImage was not found: %s\n' "$APPIMAGE_PATH" >&2
  exit 2
fi

ABSOLUTE_APPIMAGE_PATH="$(cd -- "$(dirname -- "$APPIMAGE_PATH")" && pwd)/$(basename -- "$APPIMAGE_PATH")"
readonly ABSOLUTE_APPIMAGE_PATH

printf 'Testing %s in a fresh %s container\n' \
  "$ABSOLUTE_APPIMAGE_PATH" "$CONTAINER_IMAGE"
docker run --rm --platform linux/amd64 \
  --volume "$ABSOLUTE_APPIMAGE_PATH:/artifact/Vortex.AppImage:ro" \
  --volume "$REPOSITORY_ROOT/scripts/test-appimage-container.sh:/test-appimage-container.sh:ro" \
  --volume "$REPOSITORY_ROOT/scripts/check-appimage-ui.py:/check-appimage-ui.py:ro" \
  "$CONTAINER_IMAGE" \
  bash /test-appimage-container.sh /artifact/Vortex.AppImage
