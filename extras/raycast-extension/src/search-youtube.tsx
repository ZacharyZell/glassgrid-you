import { LaunchProps, Toast, showToast } from "@raycast/api";
import { runHUDAction } from "./lib/glassgrid";

interface SearchYouTubeArgs {
  query: string;
}

export default async function SearchYouTubeCommand(props: LaunchProps<{ arguments: SearchYouTubeArgs }>) {
  const query = props.arguments.query.trim();
  if (!query) {
    await showToast({
      style: Toast.Style.Failure,
      title: "Missing Search Query",
      message: "Enter a YouTube search query.",
    });
    return;
  }

  await runHUDAction(["search", query]);
}
