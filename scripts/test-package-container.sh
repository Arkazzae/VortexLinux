#!/usr/bin/env bash

set -Eeuo pipefail

readonly SOURCE_ARTIFACT="${1:?usage: test-package-container.sh ARTIFACT}"
readonly TEST_ROOT='/tmp/vortex-package-smoke'
TEST_ARTIFACT="${TEST_ROOT}/$(basename -- "$SOURCE_ARTIFACT")"
readonly TEST_ARTIFACT
readonly STARTUP_LOG="${TEST_ROOT}/startup.log"
readonly DEPENDENCY_LOG="${TEST_ROOT}/dependencies.log"
readonly VORTEX_ROOT='/opt/Vortex'
readonly TEST_HOME='/home/vortex-test'

if command -v dotnet >/dev/null 2>&1; then
  printf 'The clean-container test image unexpectedly contains dotnet\n' >&2
  exit 1
fi

# apt reads local packages as its sandbox user, which can't see the bind mount.
install -Dm755 "$SOURCE_ARTIFACT" "$TEST_ARTIFACT"

. /etc/os-release
printf 'Testing %s on %s\n' "$(basename -- "$TEST_ARTIFACT")" "$PRETTY_NAME"

# The test harness: an X server, a D-Bus session and a DevTools client.
if command -v apt-get >/dev/null 2>&1; then
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  install_packages() {
    apt-get install --quiet=2 --no-install-recommends --yes "$@"
  }
  remove_package() {
    apt-get purge --quiet=2 --yes vortex-linux
  }
  harness=(dbus-x11 file procps python3-websocket xauth xvfb)
elif command -v dnf >/dev/null 2>&1; then
  install_packages() {
    dnf install --quiet --assumeyes --setopt=install_weak_deps=False "$@"
  }
  remove_package() {
    dnf remove --quiet --assumeyes vortex-linux
  }
  harness=(dbus-daemon file procps-ng python3-websocket-client shadow-utils
    util-linux xorg-x11-server-Xvfb xorg-x11-xauth)
elif command -v zypper >/dev/null 2>&1; then
  # Release packages are not signed.
  install_packages() {
    zypper --non-interactive --quiet install --no-recommends \
      --allow-unsigned-rpm "$@"
  }
  remove_package() {
    zypper --non-interactive --quiet remove vortex-linux
  }
  # Minimal openSUSE images lack the awk xvfb-run uses and the python3
  # command.
  harness=(dbus-1-daemon file gawk procps python3-base
    python3-websocket-client shadow util-linux xauth xvfb-run)
else
  printf 'The test image has no supported package manager\n' >&2
  exit 2
fi

case "$TEST_ARTIFACT" in
  *.AppImage)
    if ! command -v apt-get >/dev/null 2>&1; then
      printf 'The AppImage test installs its libraries with apt\n' >&2
      exit 2
    fi
    # The AppImage carries .NET. Wine and the libraries Electron needs come
    # from the system, named as in Ubuntu 24.04.
    is_package=false
    packages=(libasound2t64 libatk-bridge2.0-0 libatspi2.0-0 libcups2t64
      libdrm2 libgbm1 libgtk-3-0t64 libicu74 libnss3 libxcomposite1
      libxdamage1 libxfixes3 libxkbcommon0 libxrandr2 libxss1 wine wine64)
    ;;
  *.deb|*.rpm)
    # Only the package's own hard dependencies are installed with it.
    is_package=true
    packages=("$TEST_ARTIFACT")
    ;;
  *)
    printf 'Expected an AppImage, .deb or .rpm: %s\n' "$TEST_ARTIFACT" >&2
    exit 2
    ;;
esac

if ! install_packages "${packages[@]}" "${harness[@]}" >"$DEPENDENCY_LOG" 2>&1; then
  printf 'Unable to install the dependencies and the test harness\n' >&2
  sed -n '1,240p' "$DEPENDENCY_LOG" >&2
  exit 1
fi

if command -v dotnet >/dev/null 2>&1; then
  printf 'Host dotnet was pulled in by the dependencies; test is not hermetic\n' >&2
  exit 1
fi

runtime_commands=(dbus-run-session wine xvfb-run)
if [[ "$is_package" == true ]]; then
  runtime_commands+=(vortex)
fi
for command_name in "${runtime_commands[@]}"; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Runtime command is missing after installation: %s\n' "$command_name" >&2
    exit 1
  fi
done

if [[ "$is_package" == true ]]; then
  sandbox_mode="$(stat -c '%U:%G %a' "$VORTEX_ROOT/chrome-sandbox")"
  if [[ "$sandbox_mode" != 'root:root 4755' ]]; then
    printf 'chrome-sandbox is installed as %s, not setuid root\n' "$sandbox_mode" >&2
    exit 1
  fi

  # Every library the binaries link must come from the declared dependencies,
  # in a version this distribution has. The .NET LTTng tracing provider is
  # optional and only loaded when LTTng is installed.
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
fi

# The self-test opens no window. It runs without a display because Wine 11
# stalls while creating a prefix under Xvfb, which has no DRI3.
printf 'Running the runtime self-test without host .NET\n'
if [[ "$is_package" == true ]]; then
  ELECTRON_RUN_AS_NODE=1 VORTEX_DOTNET_WIN_ROOT="$VORTEX_ROOT/dotnet-win-x64" \
    timeout 120s "$VORTEX_ROOT/vortex" \
    /vortex-tests/test-runtime.cjs "$VORTEX_ROOT/resources/app.asar"
  DOTNET_ROOT="$VORTEX_ROOT/dotnet-linux-x64" DOTNET_ROLL_FORWARD=Major \
    "$VORTEX_ROOT/resources/app.asar.unpacked/assets/dotnetprobe" 9
else
  PREBUILDS_ONLY=1 APPIMAGE_EXTRACT_AND_RUN=1 \
    timeout 120s "$TEST_ARTIFACT" --vortex-self-test
fi

useradd --create-home --shell /bin/bash vortex-test
if [[ "$is_package" == true ]]; then
  vortex_command=vortex
else
  vortex_command="$TEST_HOME/Vortex.AppImage"
  install -o vortex-test -g vortex-test -m755 "$TEST_ARTIFACT" "$vortex_command"
fi

# The container has no FUSE, so the AppImage extracts itself.
printf 'Starting Vortex under Xvfb\n'
runuser --user vortex-test -- env \
  HOME="$TEST_HOME" \
  XDG_CONFIG_HOME="$TEST_HOME/.config" \
  XDG_DATA_HOME="$TEST_HOME/.local/share" \
  APPIMAGE_EXTRACT_AND_RUN=1 \
  dbus-run-session -- \
  xvfb-run --auto-servernum "$vortex_command" --no-sandbox \
    --remote-debugging-port=9222 >"$STARTUP_LOG" 2>&1 &
app_pid=$!
cleanup() {
  kill "$app_pid" 2>/dev/null || true
  pkill -u vortex-test 2>/dev/null || true
  wait "$app_pid" 2>/dev/null || true
}
trap cleanup EXIT

if ! python3 /check-ui.py; then
  sed -n '1,240p' "$STARTUP_LOG" >&2
  find "$TEST_HOME/.config" -name vortex.log -exec tail -n 100 {} \; >&2
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

if [[ "$is_package" == false ]]; then
  printf 'AppImage fixtures and desktop startup passed on %s without system .NET\n' \
    "$PRETTY_NAME"
  exit 0
fi

printf 'Removing the package\n'
if ! remove_package >>"$DEPENDENCY_LOG" 2>&1; then
  printf 'Unable to remove the package\n' >&2
  tail -n 60 "$DEPENDENCY_LOG" >&2
  exit 1
fi
for leftover in "$VORTEX_ROOT" /usr/bin/vortex \
    /usr/share/applications/com.nexusmods.vortex.desktop; do
  if [[ -e "$leftover" ]]; then
    printf 'Removing the package left %s behind\n' "$leftover" >&2
    exit 1
  fi
done

printf 'Package installed, started and removed cleanly on %s without system .NET\n' \
  "$PRETTY_NAME"
