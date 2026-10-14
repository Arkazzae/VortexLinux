#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_APPIMAGE="${1:?usage: test-appimage-container.sh APPIMAGE}"
readonly TEST_ROOT='/tmp/vortex-appimage-smoke'
readonly TEST_APPIMAGE="${TEST_ROOT}/Vortex.AppImage"
readonly STARTUP_LOG="${TEST_ROOT}/startup.log"
readonly DEPENDENCY_LOG="${TEST_ROOT}/dependencies.log"

if command -v dotnet >/dev/null 2>&1; then
  printf 'The clean-container test image unexpectedly contains dotnet\n' >&2
  exit 1
fi

install -Dm755 "$SOURCE_APPIMAGE" "$TEST_APPIMAGE"

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
if ! apt-get install --quiet=2 --no-install-recommends --yes \
  dbus-x11 \
  libasound2t64 \
  libatk-bridge2.0-0 \
  libatspi2.0-0 \
  libcups2t64 \
  libdrm2 \
  libgbm1 \
  libgtk-3-0t64 \
  libicu74 \
  libnss3 \
  libxcomposite1 \
  libxdamage1 \
  libxfixes3 \
  libxkbcommon0 \
  libxrandr2 \
  libxss1 \
  python3-websocket \
  wine \
  wine64 \
  xauth \
  xdg-utils \
  xvfb >"$DEPENDENCY_LOG" 2>&1; then
  printf 'Unable to install clean-container runtime dependencies\n' >&2
  sed -n '1,240p' "$DEPENDENCY_LOG" >&2
  exit 1
fi

if command -v dotnet >/dev/null 2>&1; then
  printf 'Host dotnet was pulled in by runtime dependencies; test is not hermetic\n' >&2
  exit 1
fi

for command_name in dbus-run-session wine xvfb-run; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Clean-container runtime command is missing: %s\n' "$command_name" >&2
    exit 1
  fi
done

printf 'Running AppImage runtime self-test without host .NET\n'
PREBUILDS_ONLY=1 APPIMAGE_EXTRACT_AND_RUN=1 \
  timeout 120s xvfb-run --auto-servernum "$TEST_APPIMAGE" --vortex-self-test

useradd --create-home --shell /bin/bash vortex-test
install -o vortex-test -g vortex-test -m755 "$TEST_APPIMAGE" /home/vortex-test/Vortex.AppImage

printf 'Starting the full AppImage under Xvfb\n'
runuser --user vortex-test -- env \
  HOME=/home/vortex-test \
  XDG_CONFIG_HOME=/home/vortex-test/.config \
  XDG_DATA_HOME=/home/vortex-test/.local/share \
  APPIMAGE_EXTRACT_AND_RUN=1 \
  dbus-run-session -- \
  xvfb-run --auto-servernum /home/vortex-test/Vortex.AppImage --no-sandbox \
    --disable-gpu \
    --remote-debugging-port=9222 >"$STARTUP_LOG" 2>&1 &
app_pid=$!
cleanup() {
  kill "$app_pid" 2>/dev/null || true
  pkill -u vortex-test 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
}
trap cleanup EXIT

if ! python3 /check-appimage-ui.py; then
  sed -n '1,240p' "$STARTUP_LOG" >&2
  find /home/vortex-test/.config -name vortex.log -exec tail -n 100 {} \; >&2
  exit 1
fi

sleep 5
if ! kill -0 "$app_pid" 2>/dev/null; then
  printf 'AppImage exited after loading its main page\n' >&2
  sed -n '1,240p' "$STARTUP_LOG" >&2
  exit 1
fi
if grep -Eq 'You must install \.NET|render process gone|Segmentation fault|MODULE_NOT_FOUND' "$STARTUP_LOG"; then
  printf 'AppImage reported a runtime failure\n' >&2
  sed -n '1,240p' "$STARTUP_LOG" >&2
  exit 1
fi
printf 'AppImage fixtures and desktop startup passed without system .NET\n'
