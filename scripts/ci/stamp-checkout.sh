#!/usr/bin/env bash
# Date every file of a checkout at its HEAD commit, except .git and the paths given, so a derived
# data cache built from the same commit finds them unchanged: Xcode tells a changed source by its
# mtime, and actions/checkout dates every file at the checkout. The commit's date and never a
# constant: a cache restored for another commit (restore-keys) has to see every file changed.
#
#   scripts/ci/stamp-checkout.sh DIR [EXCLUDED...]   EXCLUDED are paths relative to DIR
set -euo pipefail

dir="${1:?usage: stamp-checkout.sh DIR [EXCLUDED...]}"
dir="${dir%/}"
shift

commit="$(git -C "${dir}" rev-parse --short HEAD)"
stamp="$(TZ=UTC git -C "${dir}" log -1 --format=%cd --date=format-local:%Y%m%d%H%M.%S)"
prune=(-name .git)
for excluded in "$@"; do
  prune+=(-o -path "${dir}/${excluded%/}")
done

find "${dir}" \( "${prune[@]}" \) -prune -o -type f -exec touch -t "${stamp}" {} +
count="$(find "${dir}" \( "${prune[@]}" \) -prune -o -type f -print | wc -l | tr -d ' ')"
echo "Dated ${count} files in ${dir} at ${stamp} (UTC), the date of its commit ${commit}; left out: .git${*:+, }${*}"
