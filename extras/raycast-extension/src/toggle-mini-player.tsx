import { runHUDAction } from "./lib/glassgrid";

export default async function ToggleMiniPlayerCommand() {
  await runHUDAction(["mini-player", "toggle"]);
}
