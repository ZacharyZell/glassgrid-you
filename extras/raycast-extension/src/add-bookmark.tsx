import { LaunchProps } from "@raycast/api";
import { runHUDAction } from "./lib/glassgrid";

interface AddBookmarkArgs {
  note?: string;
}

export default async function AddBookmarkCommand(props: LaunchProps<{ arguments: AddBookmarkArgs }>) {
  const note = props.arguments.note?.trim();
  const args = note ? ["bookmark", note] : ["bookmark"];
  await runHUDAction(args);
}
