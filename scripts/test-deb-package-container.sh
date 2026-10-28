#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_PACKAGE="${1:?usage: test-deb-package-container.sh DEB}"
readonly TEST_ROOT='/tmp/vortex-deb-smoke'
readonly TEST_PACKAGE="${TEST_ROOT}/vortex-linux.deb"
readonly STARTUP_LOG="${TEST_ROOT}/startup.log"
readonly DEPENDENCY_LOG="${TEST_ROOT}/dependencies.log"
readonly VORTEX_ROOT='/opt/Vortex'

if command -v dotnet >/dev/null 2>&1; then
  printf 'The clean-container test image unexpectedly contains dotnet\n' >&2
  exit 1
fi

# apt reads local packages as its sandbox user, which can't see the bind mount.
install -Dm644 "$SOURCE_PACKAGE" "$TEST_PACKAGE"

. /etc/os-release
printf 'Installing the package on %s\n' "$PRETTY_NAME"

# Only the package's own dependencies are installed with it. The rest is the
# test harness: an X server, a D-Bus session and a DevTools client.
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
if ! apt-get install --quiet=2 --no-install-recommends --yes \
  "$TEST_PACKAGE" \
  dbus-x11 \
  file \
  procps \
  python3-websocket \
  xauth \
  xvfb >"$DEPENDENCY_LOG" 2>&1; then
  printf 'Unable to install the package and the test harness\n' >&2
  sed -n '1,240p' "$DEPENDENCY_LOG" >&2
  exit 1
fi

if command -v dotnet >/dev/null 2>&1; then
  printf 'Host dotnet was pulled in by the package dependencies; test is not hermetic\n' >&2
  exit 1
fi

for command_name in dbus-run-session vortex wine xvfb-run; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Runtime command is missing after installation: %s\n' "$command_name" >&2
    exit 1
  fi
done

sandbox_mode="$(stat -c '%U:%G %a' "$VORTEX_ROOT/chrome-sandbox")"
if [[ "$sandbox_mode" != 'root:root 4755' ]]; then
  printf 'chrome-sandbox is installed as %s, not setuid root\n' "$sandbox_mode" >&2
  exit 1
fi

# Every library the binaries link must come from the declared dependencies, in
# a version this distribution has. The .NET LTTng tracing provider is optional
# and only loaded when LTTng is installed.
printf 'Checking the shared libraries of every packaged binary\n'
unresolved=0
while IFS= read -r elf_file; do
  [[ "$elf_file" == */libcoreclrtraceptprovider.so ]] && continue
  if ! dependencies="$(ldd "$elf_file" 2>&1)"; then
    grep -Fq 'not a dynamic executable' <<< "$dependencies" && continue
  fi
  if grep -Fq 'not found' <<< "$dependencies"; then
    printf '%s:\n%s\n' "$elf_file" "$(grep -F 'not found' <<< "$dependencies")" >&2
    unresolved=1
  fi
done < <(
  find "$VORTEX_ROOT" -type f -print0 \
    | xargs -0 file --no-pad --separator '|' \
    | sed -n 's/| ELF 64-bit .*//p'
)
if ((unresolved)); then
  printf 'Packaged binaries need libraries this system does not provide\n' >&2
  exit 1
fi

printf 'Running the runtime self-test without host .NET\n'
ELECTRON_RUN_AS_NODE=1 VORTEX_DOTNET_WIN_ROOT="$VORTEX_ROOT/dotnet-win-x64" \
  timeout 120s xvfb-run --auto-servernum \
  "$VORTEX_ROOT/vortex" /vortex-tests/test-runtime.cjs "$VORTEX_ROOT/resources/app.asar"
DOTNET_ROOT="$VORTEX_ROOT/dotnet-linux-x64" DOTNET_ROLL_FORWARD=Major \
  "$VORTEX_ROOT/resources/app.asar.unpacked/assets/dotnetprobe" 9

useradd --create-home --shell /bin/bash vortex-test

printf 'Starting Vortex through its launcher under Xvfb\n'
runuser --user vortex-test -- env \
  HOME=/home/vortex-test \
  XDG_CONFIG_HOME=/home/vortex-test/.config \
  XDG_DATA_HOME=/home/vortex-test/.local/share \
  dbus-run-session -- \
  xvfb-run --auto-servernum vortex --no-sandbox \
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
  printf 'Vortex exited after loading its main page\n' >&2
  sed -n '1,240p' "$STARTUP_LOG" >&2
  exit 1
fi
if grep -Eq 'You must install \.NET|render process gone|Segmentation fault|MODULE_NOT_FOUND' "$STARTUP_LOG"; then
  printf 'Vortex reported a runtime failure\n' >&2
  sed -n '1,240p' "$STARTUP_LOG" >&2
  exit 1
fi
cleanup
trap - EXIT

printf 'Removing the package\n'
apt-get purge --quiet=2 --yes vortex-linux >>"$DEPENDENCY_LOG" 2>&1
for leftover in "$VORTEX_ROOT" /usr/bin/vortex \
    /usr/share/applications/com.nexusmods.vortex.desktop; do
  if [[ -e "$leftover" ]]; then
    printf 'Removing the package left %s behind\n' "$leftover" >&2
    exit 1
  fi
done

printf 'Package installed, started and removed cleanly on %s without system .NET\n' \
  "$PRETTY_NAME"
