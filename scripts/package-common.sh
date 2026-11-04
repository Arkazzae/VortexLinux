# Sourced by build-appimage.sh and build-distro-packages.sh, which both turn
# the Arch package into another release format. Expects REPOSITORY_ROOT.

readonly METAINFO_NAME='com.nexusmods.vortex.metainfo.xml'

# Vortex's native dotnetprobe is a framework-dependent net9.0 executable. The
# Arch package gets a host runtime through pacman, but the other formats carry
# their own: Debian has no .NET in its archive, and the startup check must
# also work on a clean distribution.
readonly DOTNET_RUNTIME_VERSION='9.0.18'
readonly DOTNET_RUNTIME_URL="https://builds.dotnet.microsoft.com/dotnet/Runtime/${DOTNET_RUNTIME_VERSION}/dotnet-runtime-${DOTNET_RUNTIME_VERSION}-linux-x64.tar.gz"
readonly DOTNET_RUNTIME_SHA512='97eb89a5a3781b9761e2a850996912ae81b96996089c78abcebbc441113457088bfcbd7cf1fa97d3036f7ac8fe22c7d30e043e93ecafc910f07b73317c73bad5'

# read_package_metadata PACKAGE
#
# Sets package_name, package_revision, package_description, package_url,
# package_license and release_version, and stops unless PACKAGE is the
# x86_64 vortex-linux package for the version in .SRCINFO.
read_package_metadata() {
  local package_path="$1"
  local package_info package_arch

  if [[ ! -f "$package_path" ]]; then
    printf 'Arch package was not found: %s\n' "$package_path" >&2
    exit 2
  fi

  package_info="$(bsdtar -xOf "$package_path" .PKGINFO)"
  package_name="$(sed -n 's/^pkgname = //p' <<< "$package_info")"
  package_revision="$(sed -n 's/^pkgver = //p' <<< "$package_info")"
  package_arch="$(sed -n 's/^arch = //p' <<< "$package_info")"
  package_description="$(sed -n 's/^pkgdesc = //p' <<< "$package_info")"
  package_url="$(sed -n 's/^url = //p' <<< "$package_info")"
  package_license="$(sed -n 's/^license = //p' <<< "$package_info")"
  release_version="$(sed -n 's/^\tpkgver = //p' "$REPOSITORY_ROOT/.SRCINFO" | head -n 1)"

  if [[ "$package_name" != vortex-linux || -z "$package_revision" || \
      -z "$release_version" || "$package_revision" != "${release_version}-"* || \
      "$package_arch" != x86_64 || -z "$package_description" || \
      -z "$package_url" || -z "$package_license" ]]; then
    printf 'Unsupported package metadata: %s %s %s\n' \
      "$package_name" "$package_revision" "$package_arch" >&2
    exit 2
  fi
}

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

# install_metainfo PATH
#
# Writes the AppStream metadata for package_revision and validates it.
install_metainfo() {
  local path="$1"

  install -dm755 "$(dirname -- "$path")"
  sed \
    -e "s/@PACKAGE_REVISION@/${package_revision}/g" \
    -e "s/@RELEASE_DATE@/$(date -u +%Y-%m-%d)/g" \
    "$REPOSITORY_ROOT/appimage/$METAINFO_NAME" > "$path"
  if grep -q '@[A-Z_]*@' "$path"; then
    printf 'The AppStream metadata still contains placeholders\n' >&2
    exit 1
  fi
  if command -v appstreamcli >/dev/null; then
    appstreamcli validate --no-net "$path"
  else
    printf 'appstreamcli is not installed; skipping AppStream validation\n' >&2
  fi
}
