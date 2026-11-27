import { runHUDAction } from "./lib/glassgrid";

export default async function TogglePlayPauseCommand() {
  await runHUDAction(["toggle"]);
}
