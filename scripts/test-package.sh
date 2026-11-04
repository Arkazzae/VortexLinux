#!/usr/bin/env bash

set -Eeuo pipefail

REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPOSITORY_ROOT
readonly ARTIFACT_PATH="${1:?usage: test-package.sh ARTIFACT [CONTAINER_IMAGE]}"
case "$ARTIFACT_PATH" in
  *.AppImage|*.deb) default_image='ubuntu:24.04' ;;
  *.rpm) default_image='fedora:44' ;;
  *)
    printf 'Expected an AppImage, .deb or .rpm: %s\n' "$ARTIFACT_PATH" >&2
    exit 2
    ;;
esac
readonly CONTAINER_IMAGE="${2:-$default_image}"

if ! command -v docker >/dev/null 2>&1; then
  printf 'Docker is required to run the clean-container smoke test\n' >&2
  exit 2
fi

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  printf 'Artifact was not found: %s\n' "$ARTIFACT_PATH" >&2
  exit 2
fi

ABSOLUTE_ARTIFACT_PATH="$(cd -- "$(dirname -- "$ARTIFACT_PATH")" && pwd)/$(basename -- "$ARTIFACT_PATH")"
readonly ABSOLUTE_ARTIFACT_PATH
readonly CONTAINER_ARTIFACT_PATH="/artifact/$(basename -- "$ARTIFACT_PATH")"

printf 'Testing %s in a fresh %s container\n' \
  "$ABSOLUTE_ARTIFACT_PATH" "$CONTAINER_IMAGE"
docker run --rm --platform linux/amd64 \
  --volume "$ABSOLUTE_ARTIFACT_PATH:$CONTAINER_ARTIFACT_PATH:ro" \
  --volume "$REPOSITORY_ROOT/scripts/test-package-container.sh:/test-package-container.sh:ro" \
  --volume "$REPOSITORY_ROOT/scripts/check-ui.py:/check-ui.py:ro" \
  --volume "$REPOSITORY_ROOT/scripts/test-runtime.cjs:/vortex-tests/test-runtime.cjs:ro" \
  --volume "$REPOSITORY_ROOT/scripts/test-loot.cjs:/vortex-tests/test-loot.cjs:ro" \
  "$CONTAINER_IMAGE" \
  bash /test-package-container.sh "$CONTAINER_ARTIFACT_PATH"
