#!/usr/bin/env bash
# Put a host app's checkout and its derived data at the same absolute paths on every runner, which
# the derived data cache needs: Xcode's build database records absolute paths, and on the
# self-hosted runners github.workspace is under a directory named for the VM. Both go under $HOME,
# the same on every VM, the checkout through a symlink at the workspace path actions/checkout
# requires. When $HOME cannot take them they stay in the workspace, where the job still works but
# a restored build is rebuilt whole.
#
#   scripts/ci/host-paths.sh CHECKOUT PREFIX DERIVED
#     CHECKOUT  checkout directory, relative to the workspace (trio)
#     PREFIX    PREFIX_DIR and PREFIX_DERIVED_DATA are written to GITHUB_ENV (TRIO)
#     DERIVED   derived data directory name (TrioDerivedData)
#   Writes derived-data, the derived data path, to GITHUB_OUTPUT.
set -euo pipefail

usage="usage: host-paths.sh CHECKOUT PREFIX DERIVED"
checkout="${1:?${usage}}"
prefix="${2:?${usage}}"
derived="${3:?${usage}}"
workspace="${GITHUB_WORKSPACE:?}"

root="${HOME:-}/tandemkit-ci"
if [[ -n "${HOME:-}" ]] && mkdir -p "${root}/${checkout}" 2>/dev/null && [[ -w "${root}/${checkout}" ]]; then
  rm -rf "${workspace:?}/${checkout}"
  ln -s "${root}/${checkout}" "${workspace}/${checkout}"
  echo "${checkout}/ and ${derived}/ under ${root}, the same path on every runner"
else
  root="${workspace}"
  echo "::warning::${HOME:-\$HOME}/tandemkit-ci is not writable: ${checkout}/ and ${derived}/ stay in the workspace, whose path differs between runners, so a restored derived data cache is rebuilt whole"
fi

{
  echo "${prefix}_DIR=${root}/${checkout}"
  echo "${prefix}_DERIVED_DATA=${root}/${derived}"
} >> "${GITHUB_ENV:?}"
echo "derived-data=${root}/${derived}" >> "${GITHUB_OUTPUT:?}"
echo "${prefix}_DIR=${root}/${checkout}"
echo "${prefix}_DERIVED_DATA=${root}/${derived}"
