import { useEffect, useMemo, useRef, useState } from "react";
import { ChevronDown, Disc3, GripVertical, Pause, Play, Plus, SkipBack, SkipForward, X } from "lucide-react";
import { ScrollArea } from "@/components/ui/scroll-area";
import { AudioQualityBadge } from "@/components/AudioQualityBadge";
import { TrackArtwork } from "@/components/TrackArtwork";
import { AudioSpectrumMeter } from "@/components/AudioSpectrumMeter";
import type { Track } from "@/hooks/useAudioQueue";
import type { TranslateFn } from "@/components/home/types";

type TouchStartState = { index: number; y: number } | null;

function EngineSpectrum({
  active,
  analyserNode,
}: {
  active: boolean;
  analyserNode: AnalyserNode | null;
}) {
  const frameRef = useRef<number | null>(null);
  const dataRef = useRef<Uint8Array<ArrayBuffer> | null>(null);
  const [bars, setBars] = useState<number[]>(() => Array.from({ length: 24 }, (_, index) => 18 + ((index * 7) % 22)));

  useEffect(() => {
    if (!active || !analyserNode || document.visibilityState !== "visible") {
      if (frameRef.current !== null) cancelAnimationFrame(frameRef.current);
      frameRef.current = null;
      return;
    }

    if (!dataRef.current || dataRef.current.length !== analyserNode.frequencyBinCount) {
      dataRef.current = new Uint8Array(analyserNode.frequencyBinCount) as Uint8Array<ArrayBuffer>;
    }

    let lastUpdate = 0;
    const tick = (time: number) => {
      if (document.visibilityState !== "visible") {
        frameRef.current = null;
        return;
      }

      analyserNode.getByteFrequencyData(dataRef.current!);
      if (time - lastUpdate > 66) {
        lastUpdate = time;
        const data = dataRef.current!;
        const stride = Math.max(1, Math.floor(data.length / 96));
        setBars((previous) =>
          previous.map((_, index) => {
            const lowBiasedIndex = Math.min(data.length - 1, 2 + index * stride);
            const value = data[lowBiasedIndex] ?? 0;
            return Math.max(8, Math.min(100, 10 + (value / 255) * 92));
          }),
        );
      }
      frameRef.current = requestAnimationFrame(tick);
    };

    frameRef.current = requestAnimationFrame(tick);
    return () => {
      if (frameRef.current !== null) cancelAnimationFrame(frameRef.current);
      frameRef.current = null;
    };
  }, [active, analyserNode]);

  return (
    <div className="mt-2 flex h-8 items-end gap-1 overflow-hidden rounded-xl border border-[var(--ep-border)] bg-black/70 px-2 py-1.5">
      {bars.map((height, index) => (
        <span
          key={index}
          className="flex-1 rounded-t-sm bg-[var(--ep-red)] shadow-[0_0_8px_rgba(255,16,42,0.35)]"
          style={{ height: `${height}%`, opacity: active ? 0.35 + (index % 5) * 0.12 : 0.16 }}
        />
      ))}
    </div>
  );
}


interface PlayerQueueState {
  queue: Track[];
  currentTrack: Track | null;
  currentTrackIndex: number;
  playTrack: (index: number) => void;
  removeFromQueue: (trackId: string) => void;
  reorderQueue: (fromIndex: number, toIndex: number) => void;
  previousTrack: () => void;
  nextTrack: () => void;
}

interface AudioProcessorState {
  currentTime: number;
  duration: number;
  isPlaying: boolean;
  seek: (time: number) => void;
  pause: () => void;
  play: () => void;
  getAnalyserNode?: () => AnalyserNode | null;
}

interface HomePlayerViewProps {
  isVisible: boolean;
  t: TranslateFn;
  showQueue: boolean;
  onToggleQueue: () => void;
  onCloseQueue: () => void;
  onOpenFilePicker: () => void;
  queue: PlayerQueueState;
  audioProcessor: AudioProcessorState;
  draggedIndex: number | null;
  onDraggedIndexChange: (index: number | null) => void;
  touchStart: TouchStartState;
  onTouchStartChange: (value: TouchStartState) => void;
  formatTime: (seconds: number) => string;
  hiresAudioBadgeUrl: string;
  epicenterEnabled: boolean;
}

export function HomePlayerView({
  isVisible,
  t,
  showQueue,
  onToggleQueue,
  onCloseQueue,
  onOpenFilePicker,
  queue,
  audioProcessor,
  draggedIndex,
  onDraggedIndexChange,
  touchStart,
  onTouchStartChange,
  formatTime,
  hiresAudioBadgeUrl,
  epicenterEnabled,
}: HomePlayerViewProps) {
  const track = queue.currentTrack;
  const analyserNode = audioProcessor.getAnalyserNode?.() ?? null;
  const qualityChips = useMemo(() => {
    if (!track) return [];
    return [
      track.bitDepth ? `${track.bitDepth} BIT` : null,
      track.sampleRate ? `${Math.round(track.sampleRate / 100) / 10} kHz` : null,
      track.bitrate ? `${Math.round(track.bitrate / 1000)} kbps` : null,
    ].filter(Boolean) as string[];
  }, [track]);

  if (!isVisible) return null;

  const progress = audioProcessor.duration > 0 ? (audioProcessor.currentTime / audioProcessor.duration) * 100 : 0;

  if (showQueue) {
    return (
      <div className="flex flex-1 flex-col px-4 pb-28 pt-12" data-testid="player-view">
        <header className="mb-4 flex items-center justify-between">
          <div>
            <p className="premium-title text-[10px] font-black text-[var(--ep-red)]">Playback Queue</p>
            <h2 className="premium-title text-xl font-black text-white">{t("player.playbackQueue")}</h2>
          </div>
          <div className="flex items-center gap-2">
            <button onClick={onOpenFilePicker} className="hardware-button rounded-full p-2 text-white"><Plus className="h-5 w-5" /></button>
            <button onClick={onCloseQueue} className="rounded-full border border-[var(--ep-border)] bg-[#111] p-2 text-[var(--ep-text-secondary)]"><ChevronDown className="h-5 w-5" /></button>
          </div>
        </header>
        <ScrollArea className="min-h-0 flex-1 rounded-3xl border border-[var(--ep-border)] bg-[#080808] p-2">
          {queue.queue.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-16 text-center">
              <Disc3 className="mb-3 h-12 w-12 text-zinc-800" strokeWidth={1} />
              <p className="text-sm text-[var(--ep-text-muted)]">{t("player.queueEmpty")}</p>
            </div>
          ) : (
            <div className="space-y-1 pb-4">
              {queue.queue.map((item, index) => {
                const isCurrent = track?.id === item.id;
                return (
                  <div key={item.id} className={`flex items-center gap-3 rounded-2xl border p-3 transition-colors ${isCurrent ? "border-[rgba(255,16,42,0.65)] bg-[#141414]" : "border-transparent hover:bg-[#101010]"}`}>
                    <div
                      className="cursor-grab touch-none p-1 text-[var(--ep-text-muted)] active:cursor-grabbing"
                      draggable
                      onDragStart={(event) => {
                        event.dataTransfer.effectAllowed = "move";
                        onDraggedIndexChange(index);
                      }}
                      onDragOver={(event) => event.preventDefault()}
                      onDrop={(event) => {
                        event.preventDefault();
                        if (draggedIndex !== null && draggedIndex !== index) queue.reorderQueue(draggedIndex, index);
                        onDraggedIndexChange(null);
                      }}
                      onDragEnd={() => onDraggedIndexChange(null)}
                      onTouchStart={(event) => {
                        event.stopPropagation();
                        onDraggedIndexChange(index);
                        onTouchStartChange({ index, y: event.touches[0].clientY });
                      }}
                      onTouchMove={(event) => {
                        event.stopPropagation();
                        if (!touchStart || draggedIndex === null) return;
                        const diff = event.touches[0].clientY - touchStart.y;
                        const newIndex = Math.max(0, Math.min(queue.queue.length - 1, touchStart.index + Math.round(diff / 72)));
                        if (newIndex !== draggedIndex) {
                          queue.reorderQueue(draggedIndex, newIndex);
                          onDraggedIndexChange(newIndex);
                        }
                      }}
                      onTouchEnd={() => {
                        onDraggedIndexChange(null);
                        onTouchStartChange(null);
                      }}
                    >
                      <GripVertical className="h-5 w-5" />
                    </div>
                    <button className="flex min-w-0 flex-1 items-center gap-3 text-left" onClick={() => queue.playTrack(index)}>
                      <div className="h-11 w-11 flex-none overflow-hidden rounded-lg border border-[var(--ep-border)] bg-[#111]"><TrackArtwork src={item.coverUrl} alt={item.title} iconClassName="h-5 w-5 text-zinc-600" /></div>
                      <div className="min-w-0 flex-1">
                        <p className={`truncate text-sm font-bold ${isCurrent ? "text-white" : "text-[var(--ep-text-secondary)]"}`}>{item.title}</p>
                        <div className="flex items-center gap-2"><p className="truncate text-xs text-[var(--ep-text-muted)]">{item.artist}</p><AudioQualityBadge bitDepth={item.bitDepth} sampleRate={item.sampleRate} bitrate={item.bitrate} isHiRes={item.isHiRes} fileExtension={item.fileName?.split(".").pop()} compact /></div>
                      </div>
                    </button>
                    <button onClick={() => queue.removeFromQueue(item.id)} className="p-2 text-zinc-600 hover:text-[var(--ep-red)]"><X className="h-4 w-4" /></button>
                  </div>
                );
              })}
            </div>
          )}
        </ScrollArea>
      </div>
    );
  }

  return (
    <div className="flex h-[100dvh] flex-col overflow-hidden px-5 pb-24 pt-10" data-testid="player-view">
      <header className="mb-3 flex shrink-0 items-center justify-between">
        <div>
          <p className="premium-title text-[10px] font-black text-[var(--ep-red)]">EpicenterDSP</p>
          <h1 className="premium-title text-xl font-black text-white">7.0 Head Unit</h1>
        </div>
        <button onClick={onToggleQueue} className="rounded-full border border-[var(--ep-border)] bg-[#0d0d0d] px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-[var(--ep-text-secondary)]">
          {t("player.queue")} ({queue.queue.length})
        </button>
      </header>

      <div className="flex min-h-0 flex-1 flex-col justify-center">
        <div className="relative mx-auto w-full max-w-[min(76vw,300px)]">
          <div className="absolute -inset-3 rounded-[2rem] bg-[radial-gradient(circle,rgba(255,16,42,0.18),transparent_64%)]" />
          <div className="album-shadow relative aspect-square overflow-hidden rounded-[1.6rem] border border-[var(--ep-border)] bg-[#101010]">
            <TrackArtwork src={track?.coverUrl} alt={track?.title || "No track"} iconClassName="h-20 w-20 text-zinc-700" />
          </div>
        </div>

        <div className="mt-4 text-center">
          <h2 className="line-clamp-2 text-2xl font-black leading-tight text-white">{track?.title || t("player.noTrack")}</h2>
          <p className="mt-1 truncate text-sm text-[var(--ep-text-secondary)]">{track?.artist || t("player.addMusic")}</p>
          {track && <div className="mt-3"><AudioQualityBadge bitDepth={track.bitDepth} sampleRate={track.sampleRate} bitrate={track.bitrate} isHiRes={track.isHiRes} fileExtension={track.fileName?.split(".").pop()} hiResLogoUrl={hiresAudioBadgeUrl} /></div>}
        </div>

        <div className="mt-4">
          <input
            type="range"
            min={0}
            max={audioProcessor.duration || 0}
            value={audioProcessor.currentTime}
            onChange={(event) => audioProcessor.seek(parseFloat(event.target.value))}
            className="progress-slider w-full"
            disabled={!track}
          />
          <div className="mt-2 flex justify-between text-[10px] font-bold tabular-nums text-[var(--ep-text-muted)]">
            <span>{formatTime(audioProcessor.currentTime)}</span>
            <span>{formatTime(audioProcessor.duration)}</span>
          </div>
        </div>

        <div className="mt-4 flex items-center justify-center gap-8">
          <button onClick={queue.previousTrack} disabled={!track} className="text-[var(--ep-text-secondary)] disabled:opacity-30"><SkipBack className="h-7 w-7" fill="currentColor" /></button>
          <button onClick={audioProcessor.isPlaying ? audioProcessor.pause : audioProcessor.play} disabled={!track} className="hardware-button flex h-16 w-16 items-center justify-center rounded-full text-white disabled:opacity-40">
            {audioProcessor.isPlaying ? <Pause className="h-7 w-7" fill="currentColor" /> : <Play className="ml-1 h-8 w-8" fill="currentColor" />}
          </button>
          <button onClick={queue.nextTrack} disabled={!track} className="text-[var(--ep-text-secondary)] disabled:opacity-30"><SkipForward className="h-7 w-7" fill="currentColor" /></button>
        </div>

        <div className="mx-auto mt-4 w-full max-w-sm rounded-2xl border border-[var(--ep-border)] bg-[var(--ep-surface)] px-4 py-3">
          <div className="mb-2 flex items-center gap-2">
            <span className="h-2 w-2 rounded-full bg-[var(--ep-red)] shadow-[0_0_9px_rgba(255,16,42,0.9)]" />
            <p className="premium-title text-[10px] font-black text-[var(--ep-text)]">Epicenter Engine Active</p>
          </div>
          <LiveEpicenterSpectrum
            analyser={audioProcessor.getAnalyserNode?.() ?? null}
            enabled={epicenterEnabled && audioProcessor.isPlaying}
            progress={progress}
          />
        </div>
      </div>
    </div>
  );
}

function LiveEpicenterSpectrum({
  analyser,
  enabled,
  progress,
}: {
  analyser: AnalyserNode | null;
  enabled: boolean;
  progress: number;
}) {
  const frameRef = useRef<number | null>(null);
  const [bars, setBars] = useState<number[]>(() => Array.from({ length: 24 }, () => 12));

  useEffect(() => {
    const stop = () => {
      if (frameRef.current !== null) {
        cancelAnimationFrame(frameRef.current);
        frameRef.current = null;
      }
    };

    if (!enabled || document.hidden) {
      stop();
      return stop;
    }

    const bins = analyser ? new Uint8Array(analyser.frequencyBinCount) : null;
    let tick = 0;

    const draw = () => {
      if (document.hidden) {
        stop();
        return;
      }

      if (analyser && bins) {
        analyser.getByteFrequencyData(bins);
        const step = Math.max(1, Math.floor(bins.length / 24));
        setBars((prev) =>
          prev.map((oldValue, index) => {
            const start = index * step;
            const slice = bins.subarray(start, start + step);
            const average = slice.reduce((sum, value) => sum + value, 0) / Math.max(1, slice.length);
            const next = 10 + (average / 255) * 90;
            return oldValue * 0.45 + next * 0.55;
          }),
        );
      } else {
        tick += 1;
        setBars((prev) =>
          prev.map((oldValue, index) => {
            const next = 16 + Math.abs(Math.sin((tick + index * 3) * 0.18)) * (28 + (progress % 32));
            return oldValue * 0.65 + next * 0.35;
          }),
        );
      }

      frameRef.current = requestAnimationFrame(draw);
    };

    frameRef.current = requestAnimationFrame(draw);
    document.addEventListener("visibilitychange", stop, { once: true });

    return () => {
      document.removeEventListener("visibilitychange", stop);
      stop();
    };
  }, [analyser, enabled, progress]);

  return (
    <div className="flex h-9 items-end gap-1 rounded-xl border border-[var(--ep-border)] bg-[var(--ep-bg)] px-2 py-1.5">
      {bars.map((height, index) => (
        <span
          key={index}
          className="flex-1 rounded-t bg-[var(--ep-red)] shadow-[0_0_8px_rgba(255,16,42,0.35)]"
          style={{ height: `${enabled ? Math.max(8, height) : 8}%`, opacity: enabled ? 0.38 + (index % 5) * 0.1 : 0.16 }}
        />
      ))}
    </div>
  );
}

export default HomePlayerView;
