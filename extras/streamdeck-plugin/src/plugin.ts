import streamDeck, {
  action,
  DialDownEvent,
  DialRotateEvent,
  KeyDownEvent,
  SingletonAction,
  TouchTapEvent,
  WillAppearEvent
} from "@elgato/streamdeck";
import { DEFAULT_MCP_HOST, DEFAULT_MCP_PORT, GlassGridMCPClient } from "./mcp-client.js";

interface GlobalPluginSettings {
  host?: string;
  port?: number;
  bearerToken?: string;
}

interface ActionSettings {
  slot?: number;
  note?: string;
  abLoopAction?: "toggle" | "set_a" | "set_b" | "clear";
  dialMode?: DialMode;
}

type DialMode = "seek" | "volume" | "frame";

const DIAL_MODES: DialMode[] = ["seek", "volume", "frame"];

const mcpClient = new GlassGridMCPClient({
  host: DEFAULT_MCP_HOST,
  port: DEFAULT_MCP_PORT,
  bearerToken: ""
});

let cachedVolumePercent = 75;

function applyGlobalSettings(settings: GlobalPluginSettings | undefined): void {
  mcpClient.updateConfig({
    host: settings?.host ?? DEFAULT_MCP_HOST,
    port: typeof settings?.port === "number" ? settings.port : DEFAULT_MCP_PORT,
    bearerToken: settings?.bearerToken ?? ""
  });
}

function slotArgs(settings: ActionSettings): Record<string, unknown> {
  if (typeof settings.slot === "number" && settings.slot >= 1 && settings.slot <= 4) {
    return { slot: settings.slot };
  }
  return {};
}

async function runTool(
  ev: { action: { showOk(): Promise<void>; showAlert(): Promise<void> } },
  toolName: string,
  args: Record<string, unknown> = {}
): Promise<void> {
  try {
    await mcpClient.callTool(toolName, args);
    await ev.action.showOk();
  } catch (err) {
    streamDeck.logger.error(`GlassGrid You tool ${toolName} failed:`, err);
    await ev.action.showAlert();
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.play-pause" })
export class PlayPauseAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    await runTool(ev, "playback_control", { action: "toggle_play_pause", ...slotArgs(ev.payload.settings) });
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.mute" })
export class MuteAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    await runTool(ev, "playback_control", { action: "toggle_mute", ...slotArgs(ev.payload.settings) });
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.mini-player" })
export class MiniPlayerAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    await runTool(ev, "mini_player_control", { action: "toggle" });
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.ghost-mode" })
export class GhostModeAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    await runTool(ev, "toggle_ghost_mode", {});
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.multiview" })
export class MultiviewAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    await runTool(ev, "multiview_control", { action: "toggle" });
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.sync-all" })
export class SyncAllAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    await runTool(ev, "sync_multiview_all", {});
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.solo-tile" })
export class SoloTileAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    const slot = ev.payload.settings.slot ?? 1;
    await runTool(ev, "multiview_control", { action: "solo", slot });
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.focus-audio" })
export class FocusAudioAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    const slot = ev.payload.settings.slot ?? 1;
    await runTool(ev, "multiview_control", { action: "focus_audio", slot });
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.add-bookmark" })
export class AddBookmarkAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    const note = ev.payload.settings.note?.trim();
    await runTool(ev, "add_bookmark", note ? { note } : {});
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.ab-loop" })
export class ToggleABLoopAction extends SingletonAction<ActionSettings> {
  override async onKeyDown(ev: KeyDownEvent<ActionSettings>): Promise<void> {
    const loopAction = ev.payload.settings.abLoopAction ?? "toggle";
    await runTool(ev, "ab_loop_control", { action: loopAction, ...slotArgs(ev.payload.settings) });
  }
}

@action({ UUID: "com.glassgridyou.streamdeck.media-dial" })
export class MediaDialAction extends SingletonAction<ActionSettings> {
  private modeLabel(mode: DialMode): string {
    switch (mode) {
      case "seek":
        return "Seek 5s";
      case "volume":
        return `Vol ${cachedVolumePercent}%`;
      case "frame":
        return "Frame";
    }
  }

  private async updateDialFeedback(
    actionObj: { setFeedback(feedback: Record<string, unknown>): Promise<void>; setTitle(title: string): Promise<void> },
    mode: DialMode,
    detail?: string
  ): Promise<void> {
    const valueText = detail ?? this.modeLabel(mode);
    await actionObj.setTitle(valueText);
    await actionObj.setFeedback({
      title: `GlassGrid (${mode.toUpperCase()})`,
      value: valueText,
      indicator: mode === "volume" ? { value: cachedVolumePercent } : undefined
    });
  }

  override async onWillAppear(ev: WillAppearEvent<ActionSettings>): Promise<void> {
    const mode = ev.payload.settings.dialMode ?? "seek";
    await this.updateDialFeedback(ev.action, mode);
  }

  override async onDialRotate(ev: DialRotateEvent<ActionSettings>): Promise<void> {
    const mode: DialMode = ev.payload.settings.dialMode ?? "seek";
    const ticks = ev.payload.ticks;
    const targetArgs = slotArgs(ev.payload.settings);

    try {
      if (mode === "seek") {
        const delta = ticks * 5;
        await mcpClient.callTool("seek_playback", { delta_seconds: delta, ...targetArgs });
        await this.updateDialFeedback(ev.action, mode, delta >= 0 ? `+${delta}s` : `${delta}s`);
      } else if (mode === "volume") {
        cachedVolumePercent = Math.min(100, Math.max(0, cachedVolumePercent + ticks * 5));
        await mcpClient.callTool("set_volume", { volume_percent: cachedVolumePercent, ...targetArgs });
        await this.updateDialFeedback(ev.action, mode, `${cachedVolumePercent}%`);
      } else {
        const direction = ticks >= 0 ? "forward" : "backward";
        const steps = Math.min(Math.abs(ticks), 5);
        for (let i = 0; i < steps; i += 1) {
          await mcpClient.callTool("step_frame", { direction, fps: 30, ...targetArgs });
        }
        await this.updateDialFeedback(ev.action, mode, direction === "forward" ? `+${steps}f` : `-${steps}f`);
      }
    } catch (err) {
      streamDeck.logger.error("GlassGrid You dial rotate failed:", err);
      await ev.action.showAlert();
    }
  }

  override async onDialDown(ev: DialDownEvent<ActionSettings>): Promise<void> {
    const current: DialMode = ev.payload.settings.dialMode ?? "seek";
    const next = DIAL_MODES[(DIAL_MODES.indexOf(current) + 1) % DIAL_MODES.length];
    const nextSettings: ActionSettings = { ...ev.payload.settings, dialMode: next };
    await ev.action.setSettings(nextSettings);
    await this.updateDialFeedback(ev.action, next);
  }

  override async onTouchTap(ev: TouchTapEvent<ActionSettings>): Promise<void> {
    try {
      await mcpClient.callTool("playback_control", {
        action: "toggle_play_pause",
        ...slotArgs(ev.payload.settings)
      });
      await ev.action.showOk();
    } catch (err) {
      streamDeck.logger.error("GlassGrid You touch tap failed:", err);
      await ev.action.showAlert();
    }
  }
}

streamDeck.settings.onDidReceiveGlobalSettings<GlobalPluginSettings>((ev) => {
  applyGlobalSettings(ev.settings);
});

streamDeck.actions.registerAction(new PlayPauseAction());
streamDeck.actions.registerAction(new MuteAction());
streamDeck.actions.registerAction(new MiniPlayerAction());
streamDeck.actions.registerAction(new GhostModeAction());
streamDeck.actions.registerAction(new MultiviewAction());
streamDeck.actions.registerAction(new SyncAllAction());
streamDeck.actions.registerAction(new SoloTileAction());
streamDeck.actions.registerAction(new FocusAudioAction());
streamDeck.actions.registerAction(new AddBookmarkAction());
streamDeck.actions.registerAction(new ToggleABLoopAction());
streamDeck.actions.registerAction(new MediaDialAction());

streamDeck.settings.getGlobalSettings<GlobalPluginSettings>().then(applyGlobalSettings).catch(() => {});
streamDeck.connect();
