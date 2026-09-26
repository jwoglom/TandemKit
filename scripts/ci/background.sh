#!/usr/bin/env bash
# Run a command detached from one CI step and collect it in a later one, so a long build can
# overlap steps that do not depend on it.
#
#   scripts/ci/background.sh start NAME CMD [ARGS...]   returns at once
#   scripts/ci/background.sh wait NAME                  streams its output, exits with its status
#
# State lives in BACKGROUND_DIR (default: $RUNNER_TEMP/background).
set -euo pipefail

dir="${BACKGROUND_DIR:-${RUNNER_TEMP:-/tmp}/background}"
action="${1:?usage: background.sh start|wait NAME [CMD...]}"
name="${2:?usage: background.sh start|wait NAME [CMD...]}"
shift 2
log="$dir/$name.log"
status="$dir/$name.status"
mkdir -p "$dir"

case "$action" in
  start)
    rm -f "$status" "$status.tmp"
    # Every descriptor is redirected: a child still holding the step's stdout keeps the runner
    # waiting for the step to finish.
    nohup bash -c '"$@"; echo $? > "$0.tmp"; mv "$0.tmp" "$0"' "$status" "$@" \
      > "$log" 2>&1 < /dev/null &
    echo "Started $name in the background (pid $!); output: $log"
    ;;
  wait)
    [[ -f "$log" ]] || { echo "$name was never started" >&2; exit 1; }
    printed=0
    while :; do
      done_=0
      [[ -f "$status" ]] && done_=1
      size=$(wc -c < "$log" | tr -d ' ')
      if (( size > printed )); then
        tail -c +"$((printed + 1))" "$log" | head -c "$((size - printed))"
        printed=$size
      fi
      (( done_ )) && break
      sleep 5
    done
    code="$(cat "$status")"
    echo "$name exited with status $code"
    exit "$code"
    ;;
  *)
    echo "unknown action $action" >&2
    exit 2
    ;;
esac
