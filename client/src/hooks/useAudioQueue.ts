/**
 * Epicenter Hi-Fi - iOS-only Audio Queue & Library Hook
 *
 * This branch is intentionally iPhone/iOS-only. The library source of truth is
 * EpicenterNative SQLite on iOS; no IndexedDB, localStorage, MediaStore, or web
 * scanner is used for tracks.
 */

import { useState, useCallback, useEffect } from "react";
import { EpicenterNative } from "@/native/iosNativeAudio";
import {
  nativeTrackToAppTrack,
  type IOSAppTrack,
} from "@/native/iosTrackMapper";

export interface Track extends IOSAppTrack {
  id: string;
  sourceTrackId?: string;
  file?: File;
  isEphemeral?: boolean;
  fileName?: string;
  fileType?: string;
  codec?: string;
  fileSize?: number;
  title: string;
  artist: string;
  duration: number;
  coverUrl?: string;
  bitDepth?: number;
  sampleRate?: number;
  bitrate?: number;
  isHiRes?: boolean;
  qualityClass?: IOSAppTrack["qualityClass"];
  sourceUri?: string;
  sourceUrl?: string;
  originalUrl?: string;
  playbackUrl?: string;
  optimizedUrl?: string;
  optimizedForPlayback?: boolean;
  optimizationStatus?: IOSAppTrack["optimizationStatus"];
  optimizationError?: string;
  originalBitDepth?: number;
  originalSampleRate?: number;
  originalBitrate?: number;
  originalFormat?: string;
  sourceType?: "manual-ios";
  albumId?: number;
  albumArtUri?: string;
  mediaStoreId?: string;
  dateModified?: number;
  sourceVersionKey?: string;
  unavailable?: boolean;
  unavailableReason?: string;
  lastSeenAt?: number;
  missingSince?: number;
  missingCount?: number;
  scanCompleteness?: "partial" | "complete";
  lastValidatedAt?: number;
}

export interface ImportResult {
  added: number;
  duplicates: string[];
}

export interface ImportProgress {
  isImporting: boolean;
  current: number;
  total: number;
  currentFileName: string;
}

export interface QueueController {
  library: Track[];
  isLoading: boolean;
  importProgress: ImportProgress;
  getTrackFile: (track: Track) => Promise<File | undefined>;
  queue: Track[];
  currentTrackIndex: number;
  currentTrack: Track | null;
  refreshLibrary: () => Promise<Track[]>;
  addToLibrary: (files: File[]) => Promise<ImportResult>;
  importManualTracksFromNativePicker: () => Promise<ImportResult>;
  addMediaStoreTracks: () => Promise<ImportResult>;
  reconcileMediaStoreTracks: () => Promise<{
    updated: number;
    missing: number;
  }>;
  removeFromLibrary: (id: string) => Promise<void>;
  clearLibrary: () => Promise<void>;
  addToQueue: (track: Track) => void;
  addToQueueNext: (track: Track) => void;
  addMultipleToQueue: (tracks: Track[]) => void;
  playAllInOrder: (tracks: Track[]) => void;
  playNow: (track: Track) => void;
  removeFromQueue: (id: string) => void;
  clearQueue: () => void;
  shuffleAll: (tracks: Track[], firstTrackId?: string) => void;
  reorderQueue: (fromIndex: number, toIndex: number) => void;
  playTrack: (index: number) => void;
  nextTrack: (requestId?: string) => void;
  previousTrack: (requestId?: string) => void;
  syncCurrentTrackById: (trackId: string) => void;
  persistEphemeralTrack: (trackId: string) => Promise<boolean>;
  addTrack: (file: File) => Promise<void>;
  addTracks: (files: File[]) => Promise<void>;
  addTrackToEnd: (track: Track) => void;
  addTrackNext: (track: Track) => void;
  removeTrack: (id: string) => void;
}

const DEFAULT_PAGE_SIZE = 1000;

const nextRequestId = (action: "next" | "previous") =>
  `webqueue-${action}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

const nativeTrackToTrack = nativeTrackToAppTrack;

const isValidTrack = (track: Track | null | undefined): track is Track =>
  Boolean(track?.id);

const setNativeQueue = async (tracks: Track[], startIndex: number) => {
  const playableTracks = Array.isArray(tracks)
    ? tracks.filter(isValidTrack)
    : [];
  if (playableTracks.length === 0) return;
  await EpicenterNative.setQueue({
    trackIds: playableTracks.map((track) => track.id),
    startIndex: Math.max(0, Math.min(startIndex, playableTracks.length - 1)),
  });
};

export function useAudioQueue(): QueueController {
  const [library, setLibrary] = useState<Track[]>([]);
  const [queue, setQueue] = useState<Track[]>([]);
  const [currentTrackIndex, setCurrentTrackIndex] = useState(-1);
  const [isLoading, setIsLoading] = useState(true);
  const [importProgress, setImportProgress] = useState<ImportProgress>({
    isImporting: false,
    current: 0,
    total: 0,
    currentFileName: "",
  });

  const refreshLibrary = useCallback(async (): Promise<Track[]> => {
    console.info("[iOS Native Library] app start load");
    setIsLoading(true);
    try {
      const page = await EpicenterNative.getLibraryPage({
        offset: 0,
        limit: DEFAULT_PAGE_SIZE,
        sort: "addedAt",
      });
      const nativeTracks = Array.isArray(page.tracks) ? page.tracks : [];
      const tracks = nativeTracks.map(nativeTrackToTrack).filter(isValidTrack);
      setLibrary(tracks);
      console.info("[iOS Native Library] loaded count", tracks.length);
      return tracks;
    } catch (error) {
      console.error("[iOS Native Library] load error", error);
      setLibrary([]);
      return [];
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void refreshLibrary();
  }, [refreshLibrary]);

  const importManualTracksFromNativePicker =
    useCallback(async (): Promise<ImportResult> => {
      console.info("[iOS Native Library] import requested");
      setImportProgress({
        isImporting: true,
        current: 0,
        total: 1,
        currentFileName: "iOS Import",
      });
      try {
        const result = await EpicenterNative.importTracks();
        console.info(
          "[iOS Native Library] imported count",
          Array.isArray(result.tracks) ? result.tracks.length : 0,
        );
        await refreshLibrary();
        return {
          added: Array.isArray(result.tracks) ? result.tracks.length : 0,
          duplicates: [],
        };
      } catch (error) {
        console.error("[iOS Native Library] import error", error);
        throw error;
      } finally {
        setImportProgress({
          isImporting: false,
          current: 0,
          total: 0,
          currentFileName: "",
        });
      }
    }, [refreshLibrary]);

  const removeFromLibrary = useCallback(async (id: string) => {
    await EpicenterNative.deleteTrack({ id });
    setLibrary((prev) => prev.filter((track) => track.id !== id));
    setQueue((prev) => prev.filter((track) => track.id !== id));
  }, []);

  const clearLibrary = useCallback(async () => {
    for (const track of library) {
      await EpicenterNative.deleteTrack({ id: track.id });
    }
    setLibrary([]);
    setQueue([]);
    setCurrentTrackIndex(-1);
  }, [library]);

  const addToQueue = useCallback(
    (track: Track) => {
      if (!isValidTrack(track)) return;
      setQueue((prev) => {
        const next = [...prev, track];
        void setNativeQueue(
          next,
          currentTrackIndex >= 0 ? currentTrackIndex : next.length - 1,
        );
        return next;
      });
    },
    [currentTrackIndex],
  );

  const addToQueueNext = useCallback(
    (track: Track) => {
      if (!isValidTrack(track)) return;
      setQueue((prev) => {
        const insertIndex = currentTrackIndex >= 0 ? currentTrackIndex + 1 : 0;
        const next = [
          ...prev.slice(0, insertIndex),
          track,
          ...prev.slice(insertIndex),
        ];
        void setNativeQueue(
          next,
          currentTrackIndex >= 0 ? currentTrackIndex : insertIndex,
        );
        return next;
      });
    },
    [currentTrackIndex],
  );

  const addMultipleToQueue = useCallback(
    (tracks: Track[]) => {
      const validTracks = Array.isArray(tracks)
        ? tracks.filter(isValidTrack)
        : [];
      if (validTracks.length === 0) return;
      setQueue((prev) => {
        const next = [...prev.filter(isValidTrack), ...validTracks];
        void setNativeQueue(
          next,
          currentTrackIndex >= 0 ? currentTrackIndex : 0,
        );
        return next;
      });
    },
    [currentTrackIndex],
  );

  const moveToQueueIndex = useCallback((index: number, reason: string) => {
    setQueue((prev) => {
      if (!Array.isArray(prev) || prev.length === 0) {
        console.warn("[Queue] move requested with empty queue", {
          reason,
          index,
        });
        setCurrentTrackIndex(-1);
        return [];
      }

      setCurrentTrackIndex((before) => {
        const after = Math.max(0, Math.min(index, prev.length - 1));
        const track = prev[after];
        console.info("[Queue] before/after index", {
          reason,
          before,
          after,
          trackId: track?.id,
          title: track?.title,
        });
        void setNativeQueue(prev, after);
        return after;
      });
      return prev;
    });
  }, []);

  const playTrack = useCallback(
    (index: number) => {
      moveToQueueIndex(index, "playTrack");
    },
    [moveToQueueIndex],
  );

  const playNow = useCallback((track: Track) => {
    if (!isValidTrack(track)) return;
    const next = [track];
    setQueue(next);
    setCurrentTrackIndex(0);
    void setNativeQueue(next, 0);
  }, []);

  const playAllInOrder = useCallback((tracks: Track[]) => {
    const validTracks = Array.isArray(tracks)
      ? tracks.filter(isValidTrack)
      : [];
    setQueue(validTracks);
    setCurrentTrackIndex(validTracks.length > 0 ? 0 : -1);
    void setNativeQueue(validTracks, 0);
  }, []);

  const shuffleAll = useCallback((tracks: Track[], firstTrackId?: string) => {
    const validTracks = Array.isArray(tracks)
      ? tracks.filter(isValidTrack)
      : [];
    const shuffled = [...validTracks].sort(() => Math.random() - 0.5);
    if (firstTrackId) {
      const firstIndex = shuffled.findIndex(
        (track) => track.id === firstTrackId,
      );
      if (firstIndex > 0) {
        const [first] = shuffled.splice(firstIndex, 1);
        shuffled.unshift(first);
      }
    }
    setQueue(shuffled);
    setCurrentTrackIndex(shuffled.length > 0 ? 0 : -1);
    void setNativeQueue(shuffled, 0);
  }, []);

  const nextTrack = useCallback((requestId = `webqueue-next-${Date.now()}`) => {
    console.info(`[WebQueue] nextTrack called requestId=${requestId} platform=ios action=delegating-to-native`, {
      currentIndex: currentTrackIndex,
      queueLength: queue.length,
    });
    void EpicenterNative.next({ requestId });
  }, [currentTrackIndex, queue.length]);

  const previousTrack = useCallback((requestId = `webqueue-previous-${Date.now()}`) => {
    console.info(`[WebQueue] previousTrack called requestId=${requestId} platform=ios action=delegating-to-native`, {
      currentIndex: currentTrackIndex,
      queueLength: queue.length,
    });
    void EpicenterNative.previous({ requestId });
  }, [currentTrackIndex, queue.length]);

  const syncCurrentTrackById = useCallback(
    (trackId: string) => {
      if (!trackId) return;
      setCurrentTrackIndex((before) => {
        const after = queue.findIndex((track) => track.id === trackId);
        if (after < 0 || after === before) return before;
        console.info("[Queue] before/after index", {
          reason: "native-sync",
          before,
          after,
          trackId,
        });
        return after;
      });
    },
    [queue],
  );

  const removeFromQueue = useCallback(
    (id: string) => {
      setQueue((prev) => {
        const next = prev.filter((track) => track.id !== id);
        setCurrentTrackIndex((current) => Math.min(current, next.length - 1));
        void setNativeQueue(
          next,
          Math.max(0, Math.min(currentTrackIndex, next.length - 1)),
        );
        return next;
      });
    },
    [currentTrackIndex],
  );

  const clearQueue = useCallback(() => {
    setQueue([]);
    setCurrentTrackIndex(-1);
    void EpicenterNative.stop();
  }, []);

  const reorderQueue = useCallback((fromIndex: number, toIndex: number) => {
    setQueue((prev) => {
      const next = [...prev];
      const [moved] = next.splice(fromIndex, 1);
      if (moved) next.splice(toIndex, 0, moved);
      setCurrentTrackIndex((current) => {
        if (current === fromIndex) return toIndex;
        if (fromIndex < current && toIndex >= current) return current - 1;
        if (fromIndex > current && toIndex <= current) return current + 1;
        return current;
      });
      void setNativeQueue(next, toIndex);
      return next;
    });
  }, []);

  const addToLibrary = useCallback(
    async () => importManualTracksFromNativePicker(),
    [importManualTracksFromNativePicker],
  );
  const addMediaStoreTracks = useCallback(
    async (): Promise<ImportResult> => ({ added: 0, duplicates: [] }),
    [],
  );
  const reconcileMediaStoreTracks = useCallback(
    async () => ({ updated: 0, missing: 0 }),
    [],
  );
  const getTrackFile = useCallback(async () => undefined, []);
  const persistEphemeralTrack = useCallback(async () => true, []);
  const addTrack = useCallback(async () => {
    await importManualTracksFromNativePicker();
  }, [importManualTracksFromNativePicker]);
  const addTracks = useCallback(async () => {
    await importManualTracksFromNativePicker();
  }, [importManualTracksFromNativePicker]);

  return {
    library,
    isLoading,
    importProgress,
    getTrackFile,
    queue,
    currentTrackIndex,
    currentTrack:
      currentTrackIndex >= 0
        ? (queue.filter(isValidTrack)[currentTrackIndex] ?? null)
        : null,
    refreshLibrary,
    addToLibrary,
    importManualTracksFromNativePicker,
    addMediaStoreTracks,
    reconcileMediaStoreTracks,
    removeFromLibrary,
    clearLibrary,
    addToQueue,
    addToQueueNext,
    addMultipleToQueue,
    playAllInOrder,
    playNow,
    removeFromQueue,
    clearQueue,
    shuffleAll,
    reorderQueue,
    playTrack,
    nextTrack,
    previousTrack,
    syncCurrentTrackById,
    persistEphemeralTrack,
    addTrack,
    addTracks,
    addTrackToEnd: addToQueue,
    addTrackNext: addToQueueNext,
    removeTrack: (id: string) => void removeFromLibrary(id),
  };
}
