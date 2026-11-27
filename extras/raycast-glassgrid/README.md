# Raycast Script Commands for GlassGrid You

Lightweight, zero-dependency Raycast Script Commands wrapping the local `glassgrid` CLI helper (`/Applications/GlassGrid You.app/Contents/MacOS/glassgrid`).

## Prerequisites

1. Install **GlassGrid You v1.4.0+** in `/Applications/GlassGrid You.app`.
2. Enable **Settings → AI & Automation → Enable AI & Automation** (with **Playback & Navigation** tier for playback/sync/ghost-mode commands, or **Full Control** for `bookmark-timestamp.sh`).

## Included Commands

| Script | Description | Mode |
| --- | --- | --- |
| `play-pause.sh` | Toggle play/pause on the active video | `silent` |
| `toggle-mini-player.sh` | Toggle Floating Mini-Player / Multiview Grid | `silent` |
| `toggle-ghost-mode.sh` | Toggle click-through Mini-Player Ghost Mode | `compact` |
| `sync-all-streams.sh` | Sync all Multiview tiles to live edge / primary tile | `compact` |
| `search-youtube.sh` | Search YouTube in a new GlassGrid You tab | `silent` |
| `bookmark-timestamp.sh` | Save a timestamped bookmark with optional note | `compact` |
| `get-transcript.sh` | Extract on-demand captions for the active YouTube video | `fullOutput` |

## Setup in Raycast

1. Open **Raycast Settings → Extensions → Script Commands**.
2. Click **Add Script Directory** and select this `extras/raycast-glassgrid` folder.
3. Optional: symlink `/Applications/GlassGrid You.app/Contents/MacOS/glassgrid` into `/usr/local/bin/glassgrid` or `/opt/homebrew/bin/glassgrid` (each script also auto-discovers the app bundle path automatically).
