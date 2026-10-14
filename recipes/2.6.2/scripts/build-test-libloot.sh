#!/usr/bin/env bash
set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly WORK_DIRECTORY="${1:?Usage: build-test-libloot.sh WORK_DIRECTORY}"
readonly commit="$(sed -n "s/^_libloot_commit='\([^']*\)'$/\1/p" "$REPOSITORY_ROOT/PKGBUILD")"
readonly checksum="$(sed -n "s/^_libloot_sha512='\([^']*\)'$/\1/p" "$REPOSITORY_ROOT/PKGBUILD")"
[[ "$commit" =~ ^[0-9a-f]{40}$ && "$checksum" =~ ^[0-9a-f]{128}$ ]]
mkdir -p "$WORK_DIRECTORY"
curl --fail --silent --show-error --location \
  "https://codeload.github.com/loot/libloot/tar.gz/$commit" \
  --output "$WORK_DIRECTORY/libloot.tar.gz"
printf '%s  %s\n' "$checksum" "$WORK_DIRECTORY/libloot.tar.gz" | sha512sum --check

tar -xzf "$WORK_DIRECTORY/libloot.tar.gz" -C "$WORK_DIRECTORY"
cd "$WORK_DIRECTORY/libloot-$commit"
LIBLOOT_REVISION="${commit:0:8}" RUSTFLAGS='-C target-cpu=x86-64' \
  cargo build --release --locked -p libloot-nodejs
install -m755 target/release/liblibloot_nodejs.so "$WORK_DIRECTORY/libloot.node"
strip --strip-unneeded "$WORK_DIRECTORY/libloot.node"
