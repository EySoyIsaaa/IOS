import { Search } from "lucide-react";
import { ScrollArea } from "@/components/ui/scroll-area";
import { SwipeableTrackItem } from "@/components/SwipeableTrackItem";
import type { Track } from "@/hooks/useAudioQueue";
import type { HomeTrackActions, TranslateFn } from "@/components/home/types";

interface HomeSearchViewProps extends HomeTrackActions {
  t: TranslateFn;
  globalSearchQuery: string;
  setGlobalSearchQuery: (value: string) => void;
  normalizedGlobalQuery: string;
  globalResults: Track[];
}

export function HomeSearchView({
  t,
  globalSearchQuery,
  setGlobalSearchQuery,
  normalizedGlobalQuery,
  globalResults,
  onPlayNow,
  onAddToQueue,
  onPlayNext,
  onAddToPlaylist,
}: HomeSearchViewProps) {
  return (
    <div className="flex-1 flex flex-col pb-32" data-testid="search-view">
      <header className="px-5 pt-12 pb-3">
        <p className="premium-title text-[10px] font-black text-[var(--ep-red)]">
          Library Search
        </p>
        <h2 className="premium-title mt-1 text-2xl font-black text-white">
          {t("search.globalTitle")}
        </h2>
        <p className="mt-1 text-xs text-[var(--ep-text-secondary)]">
          {t("search.globalSubtitle")}
        </p>
      </header>
      <div className="px-4 pt-2">
        <label className="premium-card flex items-center gap-3 rounded-2xl px-4 py-3">
          <Search className="w-5 h-5 text-[var(--ep-red)]" />
          <input
            value={globalSearchQuery}
            onChange={(event) => setGlobalSearchQuery(event.target.value)}
            placeholder={t("search.globalPlaceholder")}
            className="w-full bg-transparent text-sm font-semibold text-[var(--ep-text)] placeholder:text-[var(--ep-text-muted)] outline-none"
          />
        </label>
      </div>
      <ScrollArea className="flex-1 px-4 py-3">
        {!normalizedGlobalQuery ? (
          <div className="premium-card mx-auto mt-8 max-w-sm rounded-3xl p-6 text-center">
            <Search className="mx-auto mb-3 h-9 w-9 text-[var(--ep-red)]" />
            <p className="text-sm text-[var(--ep-text-secondary)]">
              {t("search.startTyping")}
            </p>
          </div>
        ) : globalResults.length === 0 ? (
          <div className="premium-card mx-auto mt-8 max-w-sm rounded-3xl p-6 text-center">
            <Search className="mx-auto mb-3 h-9 w-9 text-[var(--ep-text-muted)]" />
            <p className="text-sm text-[var(--ep-text-secondary)]">
              {t("search.noResults")}
            </p>
          </div>
        ) : (
          <div className="space-y-1">
            {globalResults.map((track) => (
              <SwipeableTrackItem
                key={track.id}
                track={track}
                onPlayNow={onPlayNow}
                onAddToQueue={onAddToQueue}
                onPlayNext={onPlayNext}
                onAddToPlaylist={onAddToPlaylist}
              />
            ))}
          </div>
        )}
      </ScrollArea>
    </div>
  );
}

export default HomeSearchView;
