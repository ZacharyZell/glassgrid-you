# GlassGrid You for Raycast

Official TypeScript Raycast extension for **GlassGrid You** (`v1.4.1+`), invoking the signed local `glassgrid` CLI helper via `execFile` (zero shell execution, zero external network dependencies).

## Prerequisites

1. Install **GlassGrid You v1.4.1+** in `/Applications/GlassGrid You.app`.
2. Open **GlassGrid You → Settings → AI & Automation** and turn on **Enable AI & Automation**:
   - **Read-Only** allows `Now Playing` and `Get Video Transcript`.
   - **Playback & Navigation** allows `Toggle Play / Pause`, `Search YouTube`, `Toggle Floating Mini-Player`, `Toggle Ghost Mode`, `Sync All Multiview Streams`, and `Open Streaming Service`.
   - **Full Control** is required for `Bookmark Current Timestamp`.

## Commands

| Command | Mode | Description |
| --- | --- | --- |
| `Now Playing` | View | Displays active video metadata, timeline, chapters, and quick playback controls |
| `Search YouTube` | No-View | Opens a YouTube search in a new GlassGrid You tab |
| `Toggle Play / Pause` | No-View | Plays or pauses the active video |
| `Toggle Floating Mini-Player` | No-View | Toggles the Floating Mini-Player or Floating Multiview Grid |
| `Toggle Ghost Mode` | No-View | Toggles click-through Ghost Mode on the Floating Mini-Player |
| `Sync All Multiview Streams` | No-View | Syncs all active Multiview tiles to live edge or primary stream |
| `Bookmark Current Timestamp` | No-View | Saves a timestamped bookmark with an optional note |
| `Get Video Transcript` | View | Extracts and filters on-demand YouTube captions with click-to-seek |
| `Open Streaming Service` | View | Launches any of the 18 built-in streaming services in a tab or Multiview |

## Local Development

```bash
cd extras/raycast-extension
npm install
npm run typecheck
npm run dev
```
