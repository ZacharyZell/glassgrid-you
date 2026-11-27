import { Action, ActionPanel, Icon, LaunchProps, List, Toast, showToast } from "@raycast/api";
import { useCallback, useEffect, useState } from "react";
import {
  TranscriptCue,
  TranscriptData,
  runGlassGridCommand,
  showCommandErrorToast,
} from "./lib/glassgrid";

interface GetTranscriptArgs {
  query?: string;
}

export default function GetTranscriptCommand(props: LaunchProps<{ arguments: GetTranscriptArgs }>) {
  const initialFilter = props.arguments.query?.trim() ?? "";
  const [searchText, setSearchText] = useState(initialFilter);
  const [transcript, setTranscript] = useState<TranscriptData | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  const loadTranscript = useCallback(async (queryFilter: string) => {
    setIsLoading(true);
    try {
      const args = queryFilter ? ["transcript", queryFilter] : ["transcript"];
      const outcome = await runGlassGridCommand<TranscriptData>(args, { noLaunch: true });
      setTranscript(outcome.data ?? null);
    } catch (error) {
      await showCommandErrorToast(error);
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void loadTranscript(initialFilter);
  }, [initialFilter, loadTranscript]);

  async function seekToCue(cue: TranscriptCue) {
    try {
      const targetSeconds = String(Math.max(0, Math.floor(cue.startSeconds)));
      await runGlassGridCommand(["seek", targetSeconds]);
      await showToast({
        style: Toast.Style.Success,
        title: `Seeked to ${cue.timestamp}`,
        message: cue.text,
      });
    } catch (error) {
      await showCommandErrorToast(error);
    }
  }

  const cues = (transcript?.cues ?? []).filter((cue) => {
    const q = searchText.trim().toLowerCase();
    if (!q) {
      return true;
    }
    return cue.text.toLowerCase().includes(q) || cue.timestamp.toLowerCase().includes(q);
  });

  const fullTranscriptText = cues.map((c) => `[${c.timestamp}] ${c.text}`).join("\n");

  return (
    <List
      isLoading={isLoading}
      searchText={searchText}
      onSearchTextChange={setSearchText}
      searchBarPlaceholder="Filter transcript cues..."
      navigationTitle={transcript?.title ? `Transcript · ${transcript.title}` : "Video Transcript"}
    >
      {cues.length === 0 && !isLoading ? (
        <List.EmptyView
          icon={Icon.Document}
          title="No Transcript Cues"
          description="Open a captioned YouTube video in GlassGrid You and ensure AI & Automation is enabled."
        />
      ) : (
        cues.map((cue) => (
          <List.Item
            key={cue.id}
            icon={Icon.Clock}
            title={cue.text}
            accessories={[{ text: cue.timestamp }]}
            actions={
              <ActionPanel>
                <Action title={`Jump to ${cue.timestamp}`} icon={Icon.Play} onAction={() => void seekToCue(cue)} />
                <Action.CopyToClipboard title="Copy Cue Text" content={`[${cue.timestamp}] ${cue.text}`} />
                {fullTranscriptText ? (
                  <Action.CopyToClipboard title="Copy Full Filtered Transcript" content={fullTranscriptText} />
                ) : null}
                <Action
                  title="Reload Transcript"
                  icon={Icon.ArrowClockwise}
                  onAction={() => void loadTranscript(searchText.trim())}
                />
              </ActionPanel>
            }
          />
        ))
      )}
    </List>
  );
}
