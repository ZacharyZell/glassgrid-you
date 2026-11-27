import { runHUDAction } from "./lib/glassgrid";

export default async function SyncAllStreamsCommand() {
  await runHUDAction(["sync-all"]);
}
