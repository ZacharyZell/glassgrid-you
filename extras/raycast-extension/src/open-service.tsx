import { Action, ActionPanel, Icon, List, showHUD } from "@raycast/api";
import { runGlassGridCommand, showCommandErrorToast } from "./lib/glassgrid";

interface StreamingServiceItem {
  id: string;
  name: string;
  subtitle: string;
  category: "Video & Live TV" | "Live Sports" | "Movies & Shows";
  requiresStrictDRM?: boolean;
}

const STREAMING_SERVICES: StreamingServiceItem[] = [
  { id: "youtube", name: "YouTube", subtitle: "4K HDR videos & live streams", category: "Video & Live TV" },
  { id: "yttv", name: "YouTube TV", subtitle: "Live TV & FairPlay DRM sports", category: "Video & Live TV" },
  { id: "twitch", name: "Twitch", subtitle: "Live gaming, IRL & esports", category: "Video & Live TV" },
  { id: "fubo", name: "Fubo", subtitle: "Live sports & cable channels", category: "Video & Live TV" },
  { id: "sling", name: "Sling TV", subtitle: "Live cable & news channels", category: "Video & Live TV" },
  { id: "espn", name: "ESPN / ESPN+", subtitle: "Live games, scores & ESPN+", category: "Live Sports" },
  { id: "nfl", name: "NFL+", subtitle: "Live games, RedZone & replays", category: "Live Sports" },
  { id: "nba", name: "NBA League Pass", subtitle: "Live NBA games & highlights", category: "Live Sports" },
  { id: "mlb", name: "MLB.TV", subtitle: "Live baseball & MLB Network", category: "Live Sports" },
  { id: "peacock", name: "Peacock", subtitle: "Premier League, NFL & shows", category: "Live Sports", requiresStrictDRM: true },
  { id: "paramount", name: "Paramount+", subtitle: "UEFA, NFL on CBS & films", category: "Live Sports", requiresStrictDRM: true },
  { id: "crunchyroll", name: "Crunchyroll", subtitle: "Simulcast anime & catalog", category: "Movies & Shows" },
  { id: "primevideo", name: "Prime Video", subtitle: "Thursday Night Football & originals", category: "Movies & Shows", requiresStrictDRM: true },
  { id: "disneyplus", name: "Disney+", subtitle: "Disney, Pixar, Marvel & Star Wars", category: "Movies & Shows", requiresStrictDRM: true },
  { id: "hulu", name: "Hulu", subtitle: "Live TV, FX & originals", category: "Movies & Shows", requiresStrictDRM: true },
  { id: "max", name: "Max", subtitle: "HBO originals, sports & films", category: "Movies & Shows", requiresStrictDRM: true },
  { id: "appletv", name: "Apple TV+", subtitle: "Apple Originals & MLS", category: "Movies & Shows", requiresStrictDRM: true },
  { id: "netflix", name: "Netflix", subtitle: "Series, films & live events", category: "Movies & Shows", requiresStrictDRM: true },
];

export default function OpenServiceCommand() {
  async function openInTab(service: StreamingServiceItem) {
    try {
      const outcome = await runGlassGridCommand(["service", service.id]);
      await showHUD(outcome.message);
    } catch (error) {
      await showCommandErrorToast(error);
    }
  }

  async function addToMultiview(service: StreamingServiceItem) {
    try {
      const outcome = await runGlassGridCommand(["multiview", "add", service.id]);
      await showHUD(outcome.message);
    } catch (error) {
      await showCommandErrorToast(error);
    }
  }

  return (
    <List searchBarPlaceholder="Search 18 streaming services...">
      {STREAMING_SERVICES.map((service) => (
        <List.Item
          key={service.id}
          icon={service.category === "Live Sports" ? Icon.Trophy : Icon.Video}
          title={service.name}
          subtitle={service.subtitle}
          accessories={[
            ...(service.requiresStrictDRM ? [{ tag: "Safari DRM" }] : []),
            { text: service.category },
          ]}
          actions={
            <ActionPanel>
              <Action title={`Open ${service.name} in New Tab`} icon={Icon.AppWindow} onAction={() => void openInTab(service)} />
              <Action title={`Add ${service.name} to Multiview`} icon={Icon.AppWindowGrid2x2} onAction={() => void addToMultiview(service)} />
            </ActionPanel>
          }
        />
      ))}
    </List>
  );
}
