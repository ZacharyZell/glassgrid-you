import { Action, ActionPanel, Detail, Icon, Toast, showToast } from "@raycast/api";
import { useCallback, useEffect, useState } from "react";
import {
  NowPlayingData,
  runGlassGridCommand,
  showCommandErrorToast,
} from "./lib/glassgrid";

export default function NowPlayingCommand() {
  const [data, setData] = useState<NowPlayingData | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const loadNowPlaying = useCallback(async () => {
    setIsLoading(true);
    setErrorMessage(null);
    try {
      const outcome = await runGlassGridCommand<NowPlayingData>(["now-playing"], { noLaunch: true });
      setData(outcome.data ?? { hasVideo: false });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setErrorMessage(message);
      await showCommandErrorToast(error);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadNowPlaying();
  }, [loadNowPlaying]);

  async function executeQuickAction(args: string[], label: string) {
    try {
      const outcome = await runGlassGridCommand(args);
      await showToast({ style: Toast.Style.Success, title: label, message: outcome.message });
      await loadNowPlaying();
    } catch (error) {
      await showCommandErrorToast(error);
    }
  }

  let markdown: string;
  if (errorMessage) {
    markdown = `# GlassGrid You Unavailable\n\n${errorMessage}\n\nEnsure GlassGrid You is running and **Settings → AI & Automation** is enabled.`;
  } else if (!data || !data.hasVideo) {
    markdown = `# Nothing Currently Playing\n\nOpen a video or live stream in **GlassGrid You** to inspect now-playing details here.`;
  } else {
    const statusBadge = data.isPlaying ? "Playing" : "Paused";
    const lines: string[] = [
      `# ${data.title || "Untitled Stream"}`,
      "",
      data.channel ? `**Channel:** ${data.channel}` : "",
      `**State:** ${statusBadge} · ${data.formattedTime ?? "0:00"} / ${data.formattedDuration ?? "0:00"}`,
    ].filter(Boolean);

    if (data.activeChapterTitle) {
      lines.push(`**Current Chapter:** ${data.activeChapterTitle}`);
    }

    if (data.chapters && data.chapters.length > 0) {
      lines.push("", "## Chapters", "");
      for (const ch of data.chapters.slice(0, 20)) {
        lines.push(`- \`${ch.formattedStartTime}\` — ${ch.title}`);
      }
    }

    if (data.description) {
      lines.push("", "## Description", "", data.description);
    }

    markdown = lines.join("\n");
  }

  return (
    <Detail
      isLoading={isLoading}
      markdown={markdown}
      metadata={
        data?.hasVideo ? (
          <Detail.Metadata>
            <Detail.Metadata.Label title="Status" text={data.isPlaying ? "Playing" : "Paused"} />
            <Detail.Metadata.Label
              title="Timeline"
              text={`${data.formattedTime ?? "0:00"} / ${data.formattedDuration ?? "0:00"}`}
            />
            <Detail.Metadata.Label
              title="Audio"
              text={data.isMuted ? "Muted" : `${data.volumePercent ?? 100}%`}
            />
            <Detail.Metadata.Label title="Speed" text={`${data.playbackRate ?? 1}×`} />
            {data.isHDR ? <Detail.Metadata.Label title="Video" text="HDR10" /> : null}
            {data.isCleanBoxActive ? <Detail.Metadata.Label title="Clean-Box" text="Active" /> : null}
            {data.url ? <Detail.Metadata.Link title="URL" target={data.url} text="Open Link" /> : null}
          </Detail.Metadata>
        ) : undefined
      }
      actions={
        <ActionPanel>
          <Action
            title={data?.isPlaying ? "Pause Video" : "Play Video"}
            icon={data?.isPlaying ? Icon.Pause : Icon.Play}
            onAction={() => void executeQuickAction(["toggle"], "Playback")}
          />
          <Action
            title={data?.isMuted ? "Unmute Audio" : "Mute Audio"}
            icon={Icon.SpeakerOn}
            onAction={() => void executeQuickAction([data?.isMuted ? "unmute" : "mute"], "Audio")}
          />
          <Action
            title="Bookmark Current Timestamp"
            icon={Icon.Bookmark}
            onAction={() => void executeQuickAction(["bookmark"], "Bookmarked")}
          />
          {data?.url ? <Action.CopyToClipboard title="Copy Video URL" content={data.url} /> : null}
          <Action title="Refresh" icon={Icon.ArrowClockwise} onAction={() => void loadNowPlaying()} />
        </ActionPanel>
      }
    />
  );
}
