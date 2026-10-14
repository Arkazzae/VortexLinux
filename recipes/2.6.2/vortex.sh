#!/bin/sh

export ELECTRON_TRASH="${ELECTRON_TRASH:-gio}"
# FOMOD needs build/Release.
unset PREBUILDS_ONLY

export VORTEX_DOTNET_WIN_ROOT="${VORTEX_DOTNET_WIN_ROOT:-/opt/Vortex/dotnet-win-x64}"
export VORTEX_WINEPREFIX="${VORTEX_WINEPREFIX:-${XDG_DATA_HOME:-$HOME/.local/share}/vortex-linux/wineprefix}"
export DOTNET_ROLL_FORWARD="${DOTNET_ROLL_FORWARD:-Major}"
export DOTNET_MULTILEVEL_LOOKUP="${DOTNET_MULTILEVEL_LOOKUP:-0}"

# Electron-based developer tools export this when they use Electron as their
# Node.js host. It must never leak into a normal Vortex desktop launch.
unset ELECTRON_RUN_AS_NODE

case "${1-}" in
  nxm://*) set -- --download "$@" ;;
esac

case "${VORTEX_OZONE_PLATFORM:-x11}" in
  auto) ;;
  *) set -- "--ozone-platform=${VORTEX_OZONE_PLATFORM:-x11}" --disable-vulkan "$@" ;;
esac

exec /opt/Vortex/vortex "$@"
