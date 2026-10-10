#!/usr/bin/env bash
# Decide whether a workflow's jobs need to run, and write `run`, `reason` and `marker` to
# GITHUB_OUTPUT. Any failure to decide runs them.
#
# Skips when the change only touches documentation, or when this workflow already passed on the same
# tree with the same external checkouts (the marker artifact `scripts/ci/mark-passed` uploads, named
# for them). workflow_dispatch and re-runs always run.
#
# Environment: GH_TOKEN, REPO, WORKFLOW, EVENT_NAME, RUN_ATTEMPT, DIFF_BASE, DIFF_HEAD (the two
# commits whose difference is the change under test; empty when unknown), EXTERNALS (lines of
# "<repository> <ref>" for checkouts the jobs make, empty ref = default branch, ref may be a
# comma-separated list of candidates tried in order).
set -uo pipefail

out="${GITHUB_OUTPUT:-/dev/stdout}"
docs_pattern='^(docs/.*|.*\.md|LICENSE.*)$'

emit() {
  { echo "run=$1"; echo "reason=$2"; echo "marker=${3:-}"; } >> "${out}"
  echo "run=$1 ($2)"
  exit 0
}

[[ "${EVENT_NAME}" == "workflow_dispatch" ]] && emit true "dispatched by hand"
[[ "${RUN_ATTEMPT:-1}" -gt 1 ]] && emit true "re-run"

resolve_external() {
  local repository="$1" candidates="$2" ref sha
  IFS=, read -ra refs <<< "${candidates}"
  for ref in "${refs[@]}" ""; do
    if [[ -z "${ref}" ]]; then
      sha="$(git ls-remote "https://github.com/${repository}" HEAD | cut -f1)"
    else
      sha="$(git ls-remote "https://github.com/${repository}" "refs/heads/${ref}" "refs/tags/${ref}" | head -n1 | cut -f1)"
    fi
    if [[ -n "${sha}" ]]; then
      echo "${sha}"
      return 0
    fi
  done
  return 1
}

docs_only() {
  [[ -n "${DIFF_BASE:-}" && -n "${DIFF_HEAD:-}" ]] || return 1
  local files count
  files="$(gh api "repos/${REPO}/compare/${DIFF_BASE}...${DIFF_HEAD}" --jq '.files[].filename' 2>/dev/null)" || return 1
  count="$(grep -c . <<< "${files}")"
  [[ "${count}" -gt 0 && "${count}" -lt 300 ]] || return 1
  ! grep -Evq "${docs_pattern}" <<< "${files}"
}

if docs_only; then
  emit false "only documentation changed"
fi

tree="$(git rev-parse 'HEAD^{tree}')" || emit true "could not read the tree"
key_input="${tree}"
while read -r repository ref; do
  [[ -z "${repository}" ]] && continue
  sha="$(resolve_external "${repository}" "${ref:-}")" || emit true "could not resolve ${repository}"
  key_input+=" ${repository}@${sha}"
done <<< "${EXTERNALS:-}"

key="$(sha256sum <<< "${key_input}" | cut -c1-24)"
marker="ci-passed-${WORKFLOW}-${key}"

found="$(gh api "repos/${REPO}/actions/artifacts?name=${marker}&per_page=100" \
  --jq '[.artifacts[] | select(.expired | not)] | length' 2>/dev/null)" || emit true "could not look up ${marker}" "${marker}"

if [[ "${found}" -gt 0 ]]; then
  emit false "already passed on this tree and these checkouts (${marker})" "${marker}"
fi
emit true "no earlier pass of this tree" "${marker}"
