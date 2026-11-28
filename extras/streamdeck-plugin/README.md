# GlassGrid You for Stream Deck

Official TypeScript Stream Deck & Stream Deck+ plugin (`SDKVersion: 2`, macOS 13+, Node 20) for **GlassGrid You v1.5.0+**. Communicates directly with GlassGrid You's local Streamable HTTP MCP server (`MCP-Protocol-Version: 2025-06-18`) over native `fetch`.

## Security Model

- **Strict loopback only**: `buildLoopbackMCPEndpoint` accepts only `127.0.0.1` or `localhost` on ports `1024–65535` and rejects all remote hosts.
- **Bearer token + session lifecycle**: Authenticates every request with `Authorization: Bearer <token>`, negotiates `Mcp-Session-Id` via `initialize` + `notifications/initialized`, re-initializes automatically on `404` expired sessions, and backs off cleanly on `429`.
- **Zero OS process spawning & zero external assets**: Pure local `fetch` transport and self-contained Property Inspector (`ui/settings.html` with system fonts and no external scripts or stylesheets).

## Actions

| Action | Controller | MCP Tool |
| --- | --- | --- |
| Play / Pause | Keypad | `playback_control` (`toggle_play_pause`) |
| Mute / Unmute | Keypad | `playback_control` (`toggle_mute`) |
| Mini-Player | Keypad | `mini_player_control` (`toggle`) |
| Ghost Mode | Keypad | `toggle_ghost_mode` |
| Multiview | Keypad | `multiview_control` (`toggle`) |
| Sync All | Keypad | `sync_multiview_all` |
| Solo Tile | Keypad | `multiview_control` (`solo`, slot 1–4) |
| Focus Audio | Keypad | `multiview_control` (`focus_audio`, slot 1–4) |
| Add Bookmark | Keypad | `add_bookmark` (requires Full Control) |
| Toggle A-B Loop | Keypad | `ab_loop_control` (`toggle` / `set_a` / `set_b` / `clear`) |
| Media Dial | Stream Deck+ Encoder | `seek_playback`, `set_volume`, `step_frame`, `playback_control` |

## Setup

1. Enable **AI & Automation** and **Local Streamable HTTP MCP** in **GlassGrid You → Settings → AI & Automation** (default port `41773`), then copy the Bearer token.
2. Build locally with Node 20+:
   ```bash
   cd extras/streamdeck-plugin
   npm install
   npm run build
   ```
3. Link or package `com.glassgridyou.streamdeck.sdPlugin/` into Stream Deck, then paste the Bearer token in the action Property Inspector (`ui/settings.html`).
