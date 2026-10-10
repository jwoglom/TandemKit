# Sourced, not run: starts faketandem with the virtual GATT transport on two free loopback ports
# and waits for its API. scripts/integration-test.sh and scripts/trio-test.sh share it.
#
# Reads FAKETANDEM_DIR, FAKETANDEM_JAR, FAKETANDEM_BIN, FAKETANDEM_ARGS, FAKETANDEM_HOST and LOG_DIR
# (see scripts/integration-test.sh). start_faketandem sets GATT_ADDR, API_URL and FAKETANDEM_PID;
# the caller stops it with stop_faketandem, from its own EXIT trap.

free_port() {
  python3 -c 'import socket; s=socket.socket(); s.bind(("'"$FAKETANDEM_HOST"'",0)); print(s.getsockname()[1]); s.close()'
}

start_faketandem() {
  if [[ -z "${FAKETANDEM_BIN:-}" && ! -f "$FAKETANDEM_DIR/go.mod" ]]; then
    echo "faketandem checkout not found at $FAKETANDEM_DIR; set FAKETANDEM_DIR or FAKETANDEM_BIN" >&2
    return 1
  fi
  if [[ -z "${FAKETANDEM_JAR:-}" ]]; then
    FAKETANDEM_JAR="$(ls -t "$FAKETANDEM_DIR"/third_party/pumpx2-cliparser-*.jar 2>/dev/null | head -n1 || true)"
  fi
  if [[ -z "$FAKETANDEM_JAR" || ! -f "$FAKETANDEM_JAR" ]]; then
    echo "pumpX2 cliparser jar not found; run 'make jar' in $FAKETANDEM_DIR or set FAKETANDEM_JAR" >&2
    return 1
  fi
  if ! command -v java >/dev/null; then
    echo "java is required for faketandem's JPAKE (pumpX2 jpake-server)" >&2
    return 1
  fi

  if [[ -z "${FAKETANDEM_BIN:-}" ]]; then
    echo "Building faketandem from $FAKETANDEM_DIR"
    FAKETANDEM_BIN="$LOG_DIR/faketandem"
    (cd "$FAKETANDEM_DIR" && go build -o "$FAKETANDEM_BIN" .)
  fi

  local gatt_port api_port
  gatt_port="$(free_port)"
  api_port="$(free_port)"
  GATT_ADDR="$FAKETANDEM_HOST:$gatt_port"
  API_URL="http://$FAKETANDEM_HOST:$api_port"

  # shellcheck disable=SC2206
  local extra_args=(${FAKETANDEM_ARGS:-})
  # ${arr[@]+"${arr[@]}"}: an empty array is "unbound" under set -u in macOS's bash 3.2.
  "$FAKETANDEM_BIN" -transport virtual -virtual-addr "$GATT_ADDR" -api-addr "$FAKETANDEM_HOST:$api_port" \
    -pumpx2-jar-path "$FAKETANDEM_JAR" ${extra_args[@]+"${extra_args[@]}"} > "$LOG_DIR/faketandem.log" 2>&1 &
  FAKETANDEM_PID=$!

  echo "faketandem pid $FAKETANDEM_PID; GATT $GATT_ADDR; API $API_URL"
  for _ in $(seq 1 120); do
    if curl -sf "$API_URL/api/bluetooth/pairingstate" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "$FAKETANDEM_PID" 2>/dev/null; then
      echo "faketandem exited during startup; see $LOG_DIR/faketandem.log" >&2
      tail -n 30 "$LOG_DIR/faketandem.log" >&2
      return 1
    fi
    sleep 0.5
  done
  echo "faketandem API did not come up on $API_URL" >&2
  return 1
}

stop_faketandem() {
  if [[ -n "${FAKETANDEM_PID:-}" ]] && kill -0 "$FAKETANDEM_PID" 2>/dev/null; then
    kill "$FAKETANDEM_PID" 2>/dev/null || true
    wait "$FAKETANDEM_PID" 2>/dev/null || true
  fi
  echo "faketandem log: $LOG_DIR/faketandem.log"
}
