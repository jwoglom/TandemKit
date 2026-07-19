#!/bin/bash
# SessionStart hook for Claude Code on the web.
#
# Fallback for sessions whose environment has no Setup script configured:
# runs the same idempotent bootstrap (Swift toolchain, Trio checkout,
# SwiftPM prewarm). When the environment Setup script already ran, every
# step is a fast no-op. Local (non-web) sessions are skipped entirely.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/../../scripts/claude-web-setup.sh"
