import { runHUDAction } from "./lib/glassgrid";

export default async function ToggleGhostModeCommand() {
  await runHUDAction(["ghost-mode"]);
}
