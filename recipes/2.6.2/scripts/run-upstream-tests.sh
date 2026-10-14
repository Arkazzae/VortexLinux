#!/usr/bin/env bash

set -Eeuo pipefail

readonly REPOSITORY_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly UPSTREAM_WORKTREE="${1:?Usage: scripts/run-upstream-tests.sh PATH_TO_PATCHED_VORTEX}"

if [[ ! -f "${UPSTREAM_WORKTREE}/package.json" ]]; then
  printf 'Not a Vortex source tree: %s\n' "$UPSTREAM_WORKTREE" >&2
  exit 2
fi

readonly VITEST_BIN="${UPSTREAM_WORKTREE}/node_modules/.bin/vitest"
readonly NX_BIN="${UPSTREAM_WORKTREE}/node_modules/.bin/nx"
if [[ ! -x "$VITEST_BIN" || ! -x "$NX_BIN" ]]; then
  printf 'Install upstream dependencies before running compatibility tests\n' >&2
  exit 2
fi

mapfile -t test_files < <(
  sed -nE \
    's#^diff --git a/([^ ]*\.test\.(ts|tsx)) b/.*#\1#p' \
    "${REPOSITORY_ROOT}"/patches/[0-9][0-9][0-9][0-9]-*.patch | sort -u
)

if ((${#test_files[@]} == 0)); then
  printf 'No patch-related tests were found\n' >&2
  exit 1
fi

declare -A tests_by_config=()
for test_file in "${test_files[@]}"; do
  if [[ ! -f "${UPSTREAM_WORKTREE}/${test_file}" ]]; then
    printf 'Patched test file is missing: %s\n' "$test_file" >&2
    exit 1
  fi

  search_directory="$(dirname -- "$test_file")"
  test_config=""
  while [[ "$search_directory" != "." && "$search_directory" != "/" ]]; do
    test_config="$(find "${UPSTREAM_WORKTREE}/${search_directory}" \
      -maxdepth 1 -type f \
      \( -name 'vitest.config.ts' -o -name 'vitest.config.mts' -o -name 'vitest.config.js' \) \
      -print -quit)"
    if [[ -n "$test_config" ]]; then
      break
    fi
    search_directory="$(dirname -- "$search_directory")"
  done

  if [[ -z "$test_config" ]]; then
    printf 'No project Vitest config found for: %s\n' "$test_file" >&2
    exit 1
  fi

  test_config="${test_config#"${UPSTREAM_WORKTREE}/"}"
  tests_by_config["$test_config"]+="${test_file}"$'\n'
done

printf 'Running %d patch-related test files\n' "${#test_files[@]}"
printf '  %s\n' "${test_files[@]}"

cd "$UPSTREAM_WORKTREE"
# pnpm 11 defaults to re-running install when node_modules was created with
# --ignore-scripts. Keep the compatibility job hermetic: Nx can build its own
# TypeScript dependencies, while Vortex's platform-specific install hooks must
# not run on the Linux CI host. Typechecking first also builds the workspace
# packages that the tests import, such as @vortex/nexus-api-v3.
pnpm_config_verify_deps_before_run='' \
  "$NX_BIN" run @vortex/renderer:typecheck

mapfile -t test_configs < <(printf '%s\n' "${!tests_by_config[@]}" | sort)
for test_config in "${test_configs[@]}"; do
  mapfile -t project_tests < <(printf '%s' "${tests_by_config[$test_config]}")
  config_directory="$(dirname -- "$test_config")"
  config_name="$(basename -- "$test_config")"
  relative_tests=()
  for test_file in "${project_tests[@]}"; do
    relative_tests+=("${test_file#"${config_directory}/"}")
  done

  printf '\nUsing %s\n' "$test_config"
  (
    cd "$config_directory"
    "$VITEST_BIN" --config "$config_name" run "${relative_tests[@]}"
  )
done

libloot_work_directory=''
cleanup_libloot() {
  if [[ -n "$libloot_work_directory" ]]; then
    rm -rf -- "$libloot_work_directory"
  fi
}
trap cleanup_libloot EXIT
if [[ -z "${LIBLOOT_NODE_PATH:-}" ]]; then
  libloot_work_directory="$(mktemp -d -t vortex-libloot-check.XXXXXXXX)"
  "$REPOSITORY_ROOT/scripts/build-test-libloot.sh" "$libloot_work_directory"
  export LIBLOOT_NODE_PATH="$libloot_work_directory/libloot.node"
fi
pnpm_config_verify_deps_before_run='' pnpm --filter gamebryo-plugin-management run build
pnpm_config_verify_deps_before_run='' pnpm --filter gamebryo-plugin-management run test
pnpm_config_verify_deps_before_run='' "$NX_BIN" run gamebryo-plugin-management:typecheck
node "$REPOSITORY_ROOT/scripts/test-loot.cjs" \
  "$UPSTREAM_WORKTREE/extensions/gamebryo-plugin-management/dist"
