#!/usr/bin/env bash
# Run TandemKitIntegrationTests against a freshly built faketandem.
#
# Builds faketandem from a sibling checkout, starts it with the virtual GATT
# transport on free ports, waits for its API, runs the integration tests with the
# environment they read (FaketandemHarness.swift), and tears the emulator down.
# Logs land in LOG_DIR.
#
# On macOS the tests run in the iOS simulator through scripts/test-local.sh
# (xcodebuild). On Linux they run under `swift test` in this process's
# environment, built with -DTANDEMKIT_VIRTUAL_PUMP into BUILD_PATH; Package.swift
# declares the target only when TANDEMKIT_INTEGRATION_TESTS=1, which this sets.
#
# Usage:
#   scripts/integration-test.sh                  # build + test
#   scripts/integration-test.sh test [args...]   # test without building
#   scripts/integration-test.sh build [args...]  # build only, no emulator
#   macOS: scripts/integration-test.sh test -only-testing:TandemKitIntegrationTests/PairingIntegrationTests
#   Linux: scripts/integration-test.sh test --filter TandemKitIntegrationTests.PairingIntegrationTests
#
# Environment:
#   FAKETANDEM_DIR    faketandem checkout (default: ../faketandem next to this repo).
#   FAKETANDEM_JAR    pumpX2 cliparser jar (default: newest
#                     $FAKETANDEM_DIR/third_party/pumpx2-cliparser-*.jar; `make jar` there fetches it).
#   FAKETANDEM_BIN    Prebuilt faketandem binary; skips the go build, so FAKETANDEM_DIR need only
#                     hold third_party/ (or set FAKETANDEM_JAR).
#   FAKETANDEM_ARGS   Extra flags for the emulator (e.g. "-q" for info-level logging).
#   FAKETANDEM_HOST   Interface to bind (default 127.0.0.1; the simulator shares the host network).
#   LOG_DIR           Where faketandem.log, the test log and results go (default:
#                     $DERIVED_DATA/integration-logs on macOS, $BUILD_PATH/integration-logs on Linux).
#   BUILD_PATH        Linux: swift build path (default: .build-virtual).
#   macOS: everything scripts/test-local.sh reads (TRIO_PRODUCTS, SIMULATOR, DESTINATION, and
#                     DERIVED_DATA, which defaults to .derived-data-virtual-pump here).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAKETANDEM_DIR="${FAKETANDEM_DIR:-$ROOT/../faketandem}"
FAKETANDEM_HOST="${FAKETANDEM_HOST:-127.0.0.1}"

if [[ "$(uname -s)" == "Linux" ]]; then
  LINUX=1
  BUILD_PATH="${BUILD_PATH:-$ROOT/.build-virtual}"
  LOG_DIR="${LOG_DIR:-$BUILD_PATH/integration-logs}"
  TEST_LOG="$LOG_DIR/swift-test.log"
  export TANDEMKIT_INTEGRATION_TESTS=1
  SWIFT_ARGS=(--build-path "$BUILD_PATH" -Xswiftc -DTANDEMKIT_VIRTUAL_PUMP)
else
  LINUX=0
  DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derived-data-virtual-pump}"
  LOG_DIR="${LOG_DIR:-$DERIVED_DATA/integration-logs}"
  TEST_LOG="$LOG_DIR/xcodebuild.log"
  export DERIVED_DATA
  # The harness drives the stand-in CoreBluetooth (VirtualPump.xcconfig); its own derived data keeps
  # that build from invalidating the plain one in .derived-data.
  export VIRTUAL_PUMP=1
  export SCHEME=TandemKitIntegrationTests
fi

mode="${1:-all}"; shift || true
mkdir -p "$LOG_DIR"
# faketandem is built from inside its own checkout, so relative paths would land elsewhere.
LOG_DIR="$(cd "$LOG_DIR" && pwd)"
TEST_LOG="$LOG_DIR/$(basename "$TEST_LOG")"
if [[ -d "$FAKETANDEM_DIR" ]]; then
  FAKETANDEM_DIR="$(cd "$FAKETANDEM_DIR" && pwd)"
fi

build_tests() {
  if [[ $LINUX -eq 1 ]]; then
    (cd "$ROOT" && swift build --build-tests "${SWIFT_ARGS[@]}" "$@")
  else
    "$ROOT/scripts/test-local.sh" build "$@"
  fi
}

run_tests() {
  if [[ $LINUX -eq 1 ]]; then
    local filter=(--filter TandemKitIntegrationTests)
    for arg in "$@"; do
      [[ "$arg" == "--filter" ]] && filter=()
    done
    (cd "$ROOT" && swift test --skip-build "${SWIFT_ARGS[@]}" ${filter[@]+"${filter[@]}"} "$@")
  else
    "$ROOT/scripts/test-local.sh" test -resultBundlePath "$RESULT_BUNDLE" "$@"
  fi
}

if [[ "$mode" == "build" ]]; then
  build_tests "$@"
  exit
fi

# shellcheck source=scripts/faketandem.sh
source "$ROOT/scripts/faketandem.sh"

cleanup() {
  stop_faketandem
  echo "test log: $TEST_LOG"
}
trap cleanup EXIT
start_faketandem

if [[ $LINUX -eq 1 ]]; then
  # swift test runs the tests in this process's environment.
  export FAKETANDEM_GATT="$GATT_ADDR"
  export FAKETANDEM_API_URL="$API_URL"
  export FAKETANDEM_REQUEST_LOG_DIR="$LOG_DIR/request-logs"
  rm -rf "$FAKETANDEM_REQUEST_LOG_DIR"
  mkdir -p "$FAKETANDEM_REQUEST_LOG_DIR"
else
  # xcodebuild strips the TEST_RUNNER_ prefix and hands the rest to the test process.
  export TEST_RUNNER_FAKETANDEM_GATT="$GATT_ADDR"
  export TEST_RUNNER_FAKETANDEM_API_URL="$API_URL"
  RESULT_BUNDLE="$LOG_DIR/TandemKitIntegrationTests.xcresult"
  rm -rf "$RESULT_BUNDLE"
fi
rm -f "$TEST_LOG"

set +e
if [[ "$mode" == "all" ]]; then
  # On macOS two xcodebuild runs cannot share one result bundle, so the build goes without it;
  # on Linux the arguments are swift test's (--filter), which swift build does not take.
  if [[ $LINUX -eq 1 ]]; then
    build_tests 2>&1 | tee "$TEST_LOG"
  else
    build_tests "$@" 2>&1 | tee "$TEST_LOG"
  fi
  status=${PIPESTATUS[0]}
  if [[ $status -ne 0 ]]; then
    exit "$status"
  fi
fi
run_tests "$@" 2>&1 | tee -a "$TEST_LOG"
status=${PIPESTATUS[0]}
set -e
if [[ $LINUX -eq 0 ]]; then
  echo "result bundle: $RESULT_BUNDLE"
fi
exit "$status"
