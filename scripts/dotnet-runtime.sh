# Sourced by build-appimage.sh and build-deb-package.sh.
#
# Vortex's native dotnetprobe is a framework-dependent net9.0 executable. The
# Arch package gets a host runtime through pacman, but the AppImage and the
# Debian package carry their own: Debian has no .NET in its archive, and the
# startup check must also work on a clean distribution.
readonly DOTNET_RUNTIME_VERSION='9.0.18'
readonly DOTNET_RUNTIME_URL="https://builds.dotnet.microsoft.com/dotnet/Runtime/${DOTNET_RUNTIME_VERSION}/dotnet-runtime-${DOTNET_RUNTIME_VERSION}-linux-x64.tar.gz"
readonly DOTNET_RUNTIME_SHA512='97eb89a5a3781b9761e2a850996912ae81b96996089c78abcebbc441113457088bfcbd7cf1fa97d3036f7ac8fe22c7d30e043e93ecafc910f07b73317c73bad5'

# install_dotnet_runtime DIRECTORY DOWNLOAD_PATH
install_dotnet_runtime() {
  local directory="$1"
  local archive="$2"

  curl --fail --location --silent --show-error \
    "$DOTNET_RUNTIME_URL" --output "$archive"
  printf '%s  %s\n' "$DOTNET_RUNTIME_SHA512" "$archive" \
    | sha512sum --check --status
  install -dm755 "$directory"
  bsdtar -xf "$archive" -C "$directory"

  if ! "$directory/dotnet" --list-runtimes \
      | grep -Fqx "Microsoft.NETCore.App ${DOTNET_RUNTIME_VERSION} [$directory/shared/Microsoft.NETCore.App]"; then
    printf 'The bundled .NET %s runtime is incomplete\n' "$DOTNET_RUNTIME_VERSION" >&2
    return 1
  fi
}
