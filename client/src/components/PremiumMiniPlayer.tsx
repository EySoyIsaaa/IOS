import { Pause, Play } from "lucide-react";
import { TrackArtwork } from "@/components/TrackArtwork";
import type { Track } from "@/hooks/useAudioQueue";

interface PremiumMiniPlayerProps {
  track: Track | null;
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  onPlay: () => void;
  onPause: () => void;
  onOpenPlayer: () => void;
}

export function PremiumMiniPlayer({
  track,
  isPlaying,
  currentTime,
  duration,
  onPlay,
  onPause,
  onOpenPlayer,
}: PremiumMiniPlayerProps) {
  if (!track) return null;

  const progress = duration > 0 ? Math.max(0, Math.min(100, (currentTime / duration) * 100)) : 0;

  return (
    <div className="fixed left-3 right-3 bottom-[5.9rem] z-40 rounded-2xl border border-[var(--ep-border)] bg-[#080808]/95 shadow-[0_-10px_32px_rgba(0,0,0,0.5)]">
      <div className="h-0.5 rounded-t-2xl bg-[#1b1b1b]">
        <div className="h-full rounded-tl-2xl bg-[var(--ep-red)] shadow-[0_0_12px_rgba(255,16,42,0.5)]" style={{ width: `${progress}%` }} />
      </div>
      <div className="flex items-center gap-3 px-3 py-2.5">
        <button onClick={onOpenPlayer} className="flex flex-1 items-center gap-3 overflow-hidden text-left">
          <div className="h-11 w-11 flex-none overflow-hidden rounded-lg border border-[var(--ep-border)] bg-[var(--ep-surface)]">
            <TrackArtwork src={track.coverUrl} alt={track.title} iconClassName="h-5 w-5 text-[var(--ep-text-muted)]" />
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-sm font-bold text-[var(--ep-text)]">{track.title}</p>
            <p className="truncate text-[11px] text-[var(--ep-text-secondary)]">{track.artist}</p>
          </div>
        </button>
        <button
          onClick={isPlaying ? onPause : onPlay}
          className="hardware-button flex h-10 w-10 flex-none items-center justify-center rounded-full text-white"
          aria-label={isPlaying ? "Pause" : "Play"}
        >
          {isPlaying ? <Pause className="h-4 w-4" fill="currentColor" /> : <Play className="ml-0.5 h-4 w-4" fill="currentColor" />}
        </button>
      </div>
    </div>
  );
}

export default PremiumMiniPlayer;
