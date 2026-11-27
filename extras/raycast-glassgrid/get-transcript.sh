#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Get Video Transcript
# @raycast.mode fullOutput

# Optional parameters:
# @raycast.icon 📝
# @raycast.packageName GlassGrid You
# @raycast.argument1 { "type": "text", "placeholder": "Optional filter query", "optional": true }
# @raycast.description Extract on-demand captions from the active YouTube watch page in GlassGrid You.

set -euo pipefail

GLASSGRID_BIN="${GLASSGRID_BIN:-$(command -v glassgrid || true)}"
if [[ -z "$GLASSGRID_BIN" && -x "/Applications/GlassGrid You.app/Contents/MacOS/glassgrid" ]]; then
    GLASSGRID_BIN="/Applications/GlassGrid You.app/Contents/MacOS/glassgrid"
fi
if [[ -z "$GLASSGRID_BIN" ]]; then
    echo "glassgrid CLI not found. Install GlassGrid You in /Applications." >&2
    exit 1
fi

if [[ -n "${1:-}" ]]; then
    "$GLASSGRID_BIN" transcript "$1"
else
    "$GLASSGRID_BIN" transcript
fi
