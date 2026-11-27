#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Bookmark Current Timestamp
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 🔖
# @raycast.packageName GlassGrid You
# @raycast.argument1 { "type": "text", "placeholder": "Optional note", "optional": true }
# @raycast.description Save a timestamped bookmark for the active GlassGrid You video.

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
    "$GLASSGRID_BIN" bookmark "$1"
else
    "$GLASSGRID_BIN" bookmark
fi
