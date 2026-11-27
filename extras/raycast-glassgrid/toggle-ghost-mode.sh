#!/usr/bin/env bash

# Required parameters:
# @raycast.schemaVersion 1
# @raycast.title Toggle Mini-Player Ghost Mode
# @raycast.mode compact

# Optional parameters:
# @raycast.icon 👻
# @raycast.packageName GlassGrid You
# @raycast.description Toggle click-through Ghost Mode on the Floating Mini-Player (hold Option to peek).

set -euo pipefail

GLASSGRID_BIN="${GLASSGRID_BIN:-$(command -v glassgrid || true)}"
if [[ -z "$GLASSGRID_BIN" && -x "/Applications/GlassGrid You.app/Contents/MacOS/glassgrid" ]]; then
    GLASSGRID_BIN="/Applications/GlassGrid You.app/Contents/MacOS/glassgrid"
fi
if [[ -z "$GLASSGRID_BIN" ]]; then
    echo "glassgrid CLI not found. Install GlassGrid You in /Applications." >&2
    exit 1
fi

"$GLASSGRID_BIN" ghost-mode
