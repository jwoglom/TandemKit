#!/bin/bash
# Setup script for Claude Code on the web sessions working on TandemKit.
#
# Installs a Linux Swift toolchain, checks out the Trio base repository
# (jwoglom-osaid/Trio @ dev) with this TandemKit working copy wired in as
# its TandemKit submodule path, and pre-warms the SwiftPM package caches so
# `swift build` / `swift test` run quickly inside the session.
#
# Idempotent: safe to run multiple times; every step is skipped when its
# result is already present. Intended for the environment "Setup script"
# field (runs when a new session starts, before Claude Code launches) and
# is also invoked by .claude/hooks/session-start.sh as a fallback.
#
# NOTE: the full Trio iOS app requires Xcode/macOS and cannot be compiled
# on Linux. What this environment supports is: building and testing the
# TandemKit Swift package itself (swift build / swift test of TandemCore),
# plus a Trio checkout for cross-referencing the integration (Xcode
# workspace, project.pbxproj, submodule pinning).

set -euo pipefail

log() { echo "[tandemkit-setup] $*"; }

SWIFT_VERSION="6.1.2"
SWIFT_HOME="/opt/swift"
SWIFT_URL="https://download.swift.org/swift-${SWIFT_VERSION}-release/ubuntu2404/swift-${SWIFT_VERSION}-RELEASE/swift-${SWIFT_VERSION}-RELEASE-ubuntu24.04.tar.gz"
SWIFT_SHA256="d749d5fe2d6709ee988e96b16f02bca7b53304d09925e31063fd5ec56019de9f"

# Resolve the TandemKit repo root: prefer the directory this script lives in
# (scripts/ -> repo root), fall back to $CLAUDE_PROJECT_DIR or the cwd.
if [ -n "${BASH_SOURCE:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
  REPO_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
fi
if [ ! -f "$REPO_DIR/Package.swift" ]; then
  log "ERROR: could not locate the TandemKit repo root (looked in $REPO_DIR)"
  exit 1
fi
PARENT_DIR="$(dirname "$REPO_DIR")"
TRIO_DIR="$PARENT_DIR/Trio"
TRIO_URL="https://github.com/jwoglom-osaid/Trio.git"
TRIO_BRANCH="dev"

SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  SUDO="sudo"
fi

# ---------------------------------------------------------------------------
# 1. apt dependencies required by the swift.org Ubuntu 24.04 toolchain.
# ---------------------------------------------------------------------------
APT_PACKAGES=(
  binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2
  libgcc-13-dev libpython3-dev libsqlite3-0 libstdc++-13-dev
  libxml2-dev libz3-dev pkg-config tzdata unzip zlib1g-dev
)
missing_pkgs=()
for pkg in "${APT_PACKAGES[@]}"; do
  dpkg -s "$pkg" >/dev/null 2>&1 || missing_pkgs+=("$pkg")
done
if [ "${#missing_pkgs[@]}" -gt 0 ]; then
  log "Installing apt packages: ${missing_pkgs[*]}"
  export DEBIAN_FRONTEND=noninteractive
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq "${missing_pkgs[@]}"
else
  log "apt packages already installed"
fi

# ---------------------------------------------------------------------------
# 2. Swift toolchain (official swift.org tarball) at /opt/swift
# ---------------------------------------------------------------------------
if [ -x "$SWIFT_HOME/usr/bin/swift" ] && "$SWIFT_HOME/usr/bin/swift" --version 2>/dev/null | grep -q "$SWIFT_VERSION"; then
  log "Swift $SWIFT_VERSION already installed at $SWIFT_HOME"
else
  log "Downloading Swift $SWIFT_VERSION toolchain (~880 MB)"
  tmp_tar="$(mktemp /tmp/swift-toolchain.XXXXXX.tar.gz)"
  curl -fSL --retry 3 -o "$tmp_tar" "$SWIFT_URL"
  echo "$SWIFT_SHA256  $tmp_tar" | sha256sum -c - >/dev/null
  log "Extracting toolchain to $SWIFT_HOME"
  $SUDO rm -rf "$SWIFT_HOME"
  $SUDO mkdir -p "$SWIFT_HOME"
  $SUDO tar xzf "$tmp_tar" --strip-components=1 -C "$SWIFT_HOME"
  rm -f "$tmp_tar"
fi

# Make swift available to interactive shells and to the Claude session.
$SUDO tee /etc/profile.d/swift.sh >/dev/null <<PROFILE
export PATH=$SWIFT_HOME/usr/bin:\$PATH
PROFILE
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=$SWIFT_HOME/usr/bin:\$PATH" >> "$CLAUDE_ENV_FILE"
fi
export PATH="$SWIFT_HOME/usr/bin:$PATH"
log "swift: $(swift --version 2>/dev/null | head -1)"

# ---------------------------------------------------------------------------
# 3. Trio base repository (jwoglom-osaid/Trio @ dev) as a sibling checkout,
#    with this TandemKit working copy symlinked in as the TandemKit
#    submodule path so Trio sees live edits.
#    (Note: the TandemKit submodule URL in Trio's .gitmodules is SSH-only,
#    and a recursive init would pull ~12 large unrelated LoopKit-family
#    submodules, so we intentionally do NOT run `git submodule update
#    --init --recursive`. jwoglom/Trio-tandem is not accessible
#    anonymously, hence the jwoglom-osaid/Trio fork is used.)
# ---------------------------------------------------------------------------
if [ -d "$TRIO_DIR/.git" ]; then
  log "Trio already cloned at $TRIO_DIR"
else
  log "Cloning $TRIO_URL ($TRIO_BRANCH) into $TRIO_DIR"
  git clone --depth 1 --branch "$TRIO_BRANCH" "$TRIO_URL" "$TRIO_DIR"
fi
if [ -L "$TRIO_DIR/TandemKit" ] || [ ! -e "$TRIO_DIR/TandemKit" ]; then
  ln -sfn "$REPO_DIR" "$TRIO_DIR/TandemKit"
  log "Symlinked $TRIO_DIR/TandemKit -> $REPO_DIR"
elif [ -d "$TRIO_DIR/TandemKit" ] && [ -z "$(ls -A "$TRIO_DIR/TandemKit")" ]; then
  rmdir "$TRIO_DIR/TandemKit"
  ln -sfn "$REPO_DIR" "$TRIO_DIR/TandemKit"
  log "Symlinked $TRIO_DIR/TandemKit -> $REPO_DIR"
else
  log "WARNING: $TRIO_DIR/TandemKit exists and is not empty; leaving as-is"
fi

# ---------------------------------------------------------------------------
# 4. Pre-warm SwiftPM: resolve dependencies and build TandemCore (including
#    tests) so the session starts with a hot cache. Non-fatal so a transient
#    build issue never blocks the session from starting.
# ---------------------------------------------------------------------------
cd "$REPO_DIR"
log "Resolving SwiftPM dependencies"
if swift package resolve; then
  log "Pre-building package (incl. test targets)"
  swift build --build-tests || log "WARNING: prewarm build failed; session will still start"
else
  log "WARNING: swift package resolve failed; session will still start"
fi

log "Setup complete"
