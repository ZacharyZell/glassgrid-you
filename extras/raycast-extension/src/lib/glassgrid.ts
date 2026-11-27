import { Toast, showHUD, showToast } from "@raycast/api";
import { execFile } from "node:child_process";
import { constants as fsConstants } from "node:fs";
import { access } from "node:fs/promises";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export const GLASSGRID_CLI_PATH = "/Applications/GlassGrid You.app/Contents/MacOS/glassgrid";
const FALLBACK_CLI_PATHS = ["/opt/homebrew/bin/glassgrid", "/usr/local/bin/glassgrid"] as const;
const DEFAULT_TIMEOUT_MS = 5000;

export interface AgentCommandOutcome<T = Record<string, unknown>> {
  ok: boolean;
  message: string;
  errorCode?: string;
  data?: T;
}

export interface VideoChapter {
  index: number;
  title: string;
  startSeconds: number;
  formattedStartTime: string;
}

export interface NowPlayingData {
  windowID?: string;
  tabID?: string;
  hasVideo: boolean;
  isPlaying?: boolean;
  title?: string;
  channel?: string;
  channelURL?: string;
  url?: string;
  videoID?: string;
  currentTime?: number;
  duration?: number;
  formattedTime?: string;
  formattedDuration?: string;
  isMuted?: boolean;
  volumePercent?: number;
  playbackRate?: number;
  isHDR?: boolean;
  isPiP?: boolean;
  isTheater?: boolean;
  isCleanBoxActive?: boolean;
  isAirPlayActive?: boolean;
  activeChapterTitle?: string | null;
  chapters?: VideoChapter[];
  description?: string;
}

export interface TranscriptCue {
  id: number;
  startSeconds: number;
  durationSeconds: number;
  timestamp: string;
  text: string;
}

export interface TranscriptData {
  windowID: string;
  videoID: string;
  title: string;
  languageCode: string;
  source: string;
  query: string | null;
  totalCueCount: number;
  returnedCueCount: number;
  cues: TranscriptCue[];
}

export class GlassGridCLIError extends Error {
  readonly code: string;

  constructor(code: string, message: string) {
    super(message);
    this.name = "GlassGridCLIError";
    this.code = code;
  }
}

async function isExecutable(filePath: string): Promise<boolean> {
  try {
    await access(filePath, fsConstants.X_OK);
    return true;
  } catch {
    return false;
  }
}

export async function resolveGlassGridBinary(): Promise<string> {
  if (await isExecutable(GLASSGRID_CLI_PATH)) {
    return GLASSGRID_CLI_PATH;
  }
  for (const candidate of FALLBACK_CLI_PATHS) {
    if (await isExecutable(candidate)) {
      return candidate;
    }
  }
  throw new GlassGridCLIError(
    "cli_not_found",
    `GlassGrid You CLI not found at "${GLASSGRID_CLI_PATH}". Install GlassGrid You in /Applications.`
  );
}

function parseOutcomeJSON<T>(rawStdout: string): AgentCommandOutcome<T> | null {
  const trimmed = rawStdout.trim();
  if (!trimmed) {
    return null;
  }
  try {
    const parsed = JSON.parse(trimmed) as Partial<AgentCommandOutcome<T>>;
    if (typeof parsed.ok === "boolean" && typeof parsed.message === "string") {
      return {
        ok: parsed.ok,
        message: parsed.message,
        errorCode: parsed.errorCode,
        data: parsed.data,
      };
    }
    return null;
  } catch {
    return null;
  }
}

export interface RunCommandOptions {
  noLaunch?: boolean;
  timeoutMs?: number;
}

export async function runGlassGridCommand<T = Record<string, unknown>>(
  args: string[],
  options: RunCommandOptions = {}
): Promise<AgentCommandOutcome<T>> {
  const binaryPath = await resolveGlassGridBinary();
  const fullArgs = [...args, "--json"];
  if (options.noLaunch) {
    fullArgs.push("--no-launch");
  }

  try {
    const { stdout } = await execFileAsync(binaryPath, fullArgs, {
      timeout: options.timeoutMs ?? DEFAULT_TIMEOUT_MS,
      maxBuffer: 4 * 1024 * 1024,
    });
    const outcome = parseOutcomeJSON<T>(stdout);
    if (!outcome) {
      throw new GlassGridCLIError("invalid_response", "Unexpected non-JSON response from glassgrid CLI.");
    }
    if (!outcome.ok) {
      throw new GlassGridCLIError(outcome.errorCode ?? "command_failed", outcome.message);
    }
    return outcome;
  } catch (error) {
    if (error instanceof GlassGridCLIError) {
      throw error;
    }
    const execErr = error as { stdout?: string; stderr?: string; message?: string; killed?: boolean };
    if (typeof execErr.stdout === "string") {
      const outcome = parseOutcomeJSON<T>(execErr.stdout);
      if (outcome) {
        throw new GlassGridCLIError(outcome.errorCode ?? "command_failed", outcome.message);
      }
    }
    if (execErr.killed) {
      throw new GlassGridCLIError("timeout", "Timed out waiting for GlassGrid You.");
    }
    const stderr = typeof execErr.stderr === "string" ? execErr.stderr.trim() : "";
    throw new GlassGridCLIError(
      "cli_error",
      stderr || execErr.message || "Failed to execute glassgrid CLI."
    );
  }
}

export async function runHUDAction(args: string[], successPrefix?: string): Promise<void> {
  try {
    const outcome = await runGlassGridCommand(args);
    const label = successPrefix ? `${successPrefix}: ${outcome.message}` : outcome.message;
    await showHUD(label);
  } catch (error) {
    await showCommandErrorToast(error);
  }
}

export async function showCommandErrorToast(error: unknown): Promise<void> {
  if (error instanceof GlassGridCLIError) {
    const title =
      error.code === "automation_disabled"
        ? "AI & Automation Disabled"
        : error.code === "permission_denied"
          ? "Permission Tier Too Low"
          : error.code === "cli_not_found"
            ? "GlassGrid You Not Installed"
            : "GlassGrid You Error";
    await showToast({
      style: Toast.Style.Failure,
      title,
      message: error.message,
    });
    return;
  }

  await showToast({
    style: Toast.Style.Failure,
    title: "GlassGrid You Error",
    message: error instanceof Error ? error.message : String(error),
  });
}
