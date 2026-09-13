#!/usr/bin/env bash
# Build and run TandemKitTests locally without a Loop/Trio workspace.
#
# TandemKit.xcodeproj links LoopKit, LoopKitUI and their dependencies from
# BUILT_PRODUCTS_DIR, so this stages already-built simulator products from a
# Trio DerivedData directory into a private derived-data path, then runs
# xcodebuild there. The staged products must have been built with the same
# Xcode toolchain currently selected.
#
# Usage:
#   scripts/test-local.sh                   # build-for-testing + test TandemKitTests
#   scripts/test-local.sh build             # build-for-testing only
#   scripts/test-local.sh test [xcodebuild args...]
#
# Environment:
#   TRIO_PRODUCTS   Trio Debug-iphonesimulator products dir. Defaults to the newest
#                   ~/Library/Developer/Xcode/DerivedData/Trio-*/Build/Products/Debug-iphonesimulator
#                   that contains LoopKit.framework.
#   DERIVED_DATA    Where to build (default: .derived-data in the repo root).
#   SIMULATOR       Simulator name (default: first available iPhone).
#   SCHEME          Scheme to test (default: TandemKitTests).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derived-data}"
SCHEME="${SCHEME:-TandemKitTests}"
PRODUCTS="$DERIVED_DATA/Build/Products/Debug-iphonesimulator"

if [[ -z "${TRIO_PRODUCTS:-}" ]]; then
  TRIO_PRODUCTS="$(ls -td ~/Library/Developer/Xcode/DerivedData/Trio-*/Build/Products/Debug-iphonesimulator 2>/dev/null \
    | while read -r d; do [[ -d "$d/LoopKit.framework" ]] && echo "$d" && break; done)"
fi
if [[ -z "${TRIO_PRODUCTS:-}" || ! -d "$TRIO_PRODUCTS/LoopKit.framework" ]]; then
  echo "No Trio simulator products with LoopKit.framework found; set TRIO_PRODUCTS" >&2
  exit 1
fi

if [[ -z "${SIMULATOR:-}" ]]; then
  SIMULATOR="$(xcrun simctl list devices available | grep -m1 -oE 'iPhone [^(]+' | sed 's/ *$//')"
fi

mkdir -p "$PRODUCTS"
# LoopKitUI's module interface pulls in these package products too.
for item in LoopKit.framework LoopKitUI.framework \
            SwiftCharts.swiftmodule SwiftCharts.o \
            LoopAlgorithm.swiftmodule LoopAlgorithm.o \
            MKRingProgressView.swiftmodule MKRingProgressView.o; do
  if [[ -e "$TRIO_PRODUCTS/$item" ]]; then
    rsync -a "$TRIO_PRODUCTS/$item" "$PRODUCTS/"
  fi
done

COMMON=(-project "$ROOT/TandemKit.xcodeproj" -scheme "$SCHEME" -configuration Debug
        -destination "platform=iOS Simulator,name=$SIMULATOR" -derivedDataPath "$DERIVED_DATA"
        -skipMacroValidation -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO)

mode="${1:-all}"; shift || true
echo "Staged LoopKit from: $TRIO_PRODUCTS"
echo "Simulator: $SIMULATOR   Derived data: $DERIVED_DATA"
case "$mode" in
  build) xcodebuild build-for-testing "${COMMON[@]}" "$@" ;;
  test)  xcodebuild test-without-building "${COMMON[@]}" "$@" ;;
  all)   xcodebuild build-for-testing "${COMMON[@]}" "$@"
         xcodebuild test-without-building "${COMMON[@]}" "$@" ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
