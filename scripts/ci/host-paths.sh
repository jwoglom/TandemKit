#!/usr/bin/env bash
# Put a host app's checkout and its derived data at the same absolute paths on every runner, which
# the derived data cache needs: Xcode's build database records absolute paths, and on the
# self-hosted runners github.workspace is under a directory named for the VM. Both go under $HOME,
# the same on every VM. Run after the checkout, which has to be made at the workspace path:
# actions/checkout grants its token to the repository by that path (an includeIf on the git dir),
# and git names a git dir by its real path, so a checkout made through a symlink fetches with no
# credentials. The checkout is moved under $HOME and a symlink left at the workspace path for the
# steps that still name it there. When $HOME cannot take them they stay in the workspace, where the
# job still works but a restored build is rebuilt whole.
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
if [[ -n "${HOME:-}" && -d "${workspace}/${checkout}" && ! -L "${workspace}/${checkout}" ]] \
  && mkdir -p "${root}" 2>/dev/null && [[ -w "${root}" && ! -e "${root}/${checkout}" ]] \
  && mv "${workspace}/${checkout}" "${root}/${checkout}"; then
  ln -s "${root}/${checkout}" "${workspace}/${checkout}"
  echo "${checkout}/ moved under ${root}, with ${derived}/, the same path on every runner"
else
  root="${workspace}"
  echo "::warning::${HOME:-\$HOME}/tandemkit-ci cannot take ${checkout}/: it and ${derived}/ stay in the workspace, whose path differs between runners, so a restored derived data cache is rebuilt whole"
fi

{
  echo "${prefix}_DIR=${root}/${checkout}"
  echo "${prefix}_DERIVED_DATA=${root}/${derived}"
} >> "${GITHUB_ENV:?}"
echo "derived-data=${root}/${derived}" >> "${GITHUB_OUTPUT:?}"
echo "${prefix}_DIR=${root}/${checkout}"
echo "${prefix}_DERIVED_DATA=${root}/${derived}"
