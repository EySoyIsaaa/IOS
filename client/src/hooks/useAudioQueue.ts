/**
 * Epicenter Hi-Fi - iOS-only Audio Queue & Library Hook
 *
 * This branch is intentionally iPhone/iOS-only. The library source of truth is
 * EpicenterNative SQLite on iOS; no IndexedDB, localStorage, MediaStore, or web
 * scanner is used for tracks.
 */

import { useState, useCallback, useEffect } from 'react';
import { EpicenterNative } from '@/native/iosNativeAudio';
import { nativeTrackToAppTrack, type IOSAppTrack } from '@/native/iosTrackMapper';

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
  sourceUri?: string;
  sourceType?: 'manual-ios';
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
  scanCompleteness?: 'partial' | 'complete';
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
  reconcileMediaStoreTracks: () => Promise<{ updated: number; missing: number }>;
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
  nextTrack: () => void;
  previousTrack: () => void;
  persistEphemeralTrack: (trackId: string) => Promise<boolean>;
  addTrack: (file: File) => Promise<void>;
  addTracks: (files: File[]) => Promise<void>;
  addTrackToEnd: (track: Track) => void;
  addTrackNext: (track: Track) => void;
  removeTrack: (id: string) => void;
}

const DEFAULT_PAGE_SIZE = 1000;

const nativeTrackToTrack = nativeTrackToAppTrack;


const setNativeQueue = async (tracks: Track[], startIndex: number) => {
  if (tracks.length === 0) return;
  await EpicenterNative.setQueue({
    trackIds: tracks.map((track) => track.id),
    startIndex: Math.max(0, Math.min(startIndex, tracks.length - 1)),
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
    currentFileName: '',
  });

  const refreshLibrary = useCallback(async (): Promise<Track[]> => {
    console.info('[iOS Native Library] app start load');
    setIsLoading(true);
    try {
      const page = await EpicenterNative.getLibraryPage({ offset: 0, limit: DEFAULT_PAGE_SIZE, sort: 'addedAt' });
      const tracks = page.tracks.map(nativeTrackToTrack);
      setLibrary(tracks);
      console.info('[iOS Native Library] loaded count', tracks.length);
      return tracks;
    } catch (error) {
      console.error('[iOS Native Library] load error', error);
      setLibrary([]);
      return [];
    } finally {
      setIsLoading(false);
    }
  }, []);

  useEffect(() => {
    void refreshLibrary();
  }, [refreshLibrary]);

  const importManualTracksFromNativePicker = useCallback(async (): Promise<ImportResult> => {
    console.info('[iOS Native Library] import requested');
    setImportProgress({ isImporting: true, current: 0, total: 1, currentFileName: 'iOS Import' });
    try {
      const result = await EpicenterNative.importTracks();
      console.info('[iOS Native Library] imported count', result.tracks.length);
      await refreshLibrary();
      return { added: result.tracks.length, duplicates: [] };
    } catch (error) {
      console.error('[iOS Native Library] import error', error);
      throw error;
    } finally {
      setImportProgress({ isImporting: false, current: 0, total: 0, currentFileName: '' });
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

  const addToQueue = useCallback((track: Track) => {
    setQueue((prev) => {
      const next = [...prev, track];
      void setNativeQueue(next, currentTrackIndex >= 0 ? currentTrackIndex : next.length - 1);
      return next;
    });
  }, [currentTrackIndex]);

  const addToQueueNext = useCallback((track: Track) => {
    setQueue((prev) => {
      const insertIndex = currentTrackIndex >= 0 ? currentTrackIndex + 1 : 0;
      const next = [...prev.slice(0, insertIndex), track, ...prev.slice(insertIndex)];
      void setNativeQueue(next, currentTrackIndex >= 0 ? currentTrackIndex : insertIndex);
      return next;
    });
  }, [currentTrackIndex]);

  const addMultipleToQueue = useCallback((tracks: Track[]) => {
    setQueue((prev) => {
      const next = [...prev, ...tracks];
      void setNativeQueue(next, currentTrackIndex >= 0 ? currentTrackIndex : 0);
      return next;
    });
  }, [currentTrackIndex]);

  const playTrack = useCallback((index: number) => {
    setCurrentTrackIndex(index);
    setQueue((prev) => {
      void setNativeQueue(prev, index);
      return prev;
    });
  }, []);

  const playNow = useCallback((track: Track) => {
    const next = [track];
    setQueue(next);
    setCurrentTrackIndex(0);
    void setNativeQueue(next, 0);
  }, []);

  const playAllInOrder = useCallback((tracks: Track[]) => {
    setQueue(tracks);
    setCurrentTrackIndex(tracks.length > 0 ? 0 : -1);
    void setNativeQueue(tracks, 0);
  }, []);

  const shuffleAll = useCallback((tracks: Track[], firstTrackId?: string) => {
    const shuffled = [...tracks].sort(() => Math.random() - 0.5);
    if (firstTrackId) {
      const firstIndex = shuffled.findIndex((track) => track.id === firstTrackId);
      if (firstIndex > 0) {
        const [first] = shuffled.splice(firstIndex, 1);
        shuffled.unshift(first);
      }
    }
    setQueue(shuffled);
    setCurrentTrackIndex(shuffled.length > 0 ? 0 : -1);
    void setNativeQueue(shuffled, 0);
  }, []);

  const nextTrack = useCallback(() => {
    setCurrentTrackIndex((prev) => {
      const next = prev < queue.length - 1 ? prev + 1 : prev;
      if (next !== prev) void EpicenterNative.next();
      return next;
    });
  }, [queue.length]);

  const previousTrack = useCallback(() => {
    setCurrentTrackIndex((prev) => {
      const next = prev > 0 ? prev - 1 : prev;
      if (next !== prev) void EpicenterNative.previous();
      return next;
    });
  }, []);

  const removeFromQueue = useCallback((id: string) => {
    setQueue((prev) => {
      const next = prev.filter((track) => track.id !== id);
      setCurrentTrackIndex((current) => Math.min(current, next.length - 1));
      void setNativeQueue(next, Math.max(0, Math.min(currentTrackIndex, next.length - 1)));
      return next;
    });
  }, [currentTrackIndex]);

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

  const addToLibrary = useCallback(async () => importManualTracksFromNativePicker(), [importManualTracksFromNativePicker]);
  const addMediaStoreTracks = useCallback(async (): Promise<ImportResult> => ({ added: 0, duplicates: [] }), []);
  const reconcileMediaStoreTracks = useCallback(async () => ({ updated: 0, missing: 0 }), []);
  const getTrackFile = useCallback(async () => undefined, []);
  const persistEphemeralTrack = useCallback(async () => true, []);
  const addTrack = useCallback(async () => { await importManualTracksFromNativePicker(); }, [importManualTracksFromNativePicker]);
  const addTracks = useCallback(async () => { await importManualTracksFromNativePicker(); }, [importManualTracksFromNativePicker]);

  return {
    library,
    isLoading,
    importProgress,
    getTrackFile,
    queue,
    currentTrackIndex,
    currentTrack: currentTrackIndex >= 0 ? queue[currentTrackIndex] ?? null : null,
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
    persistEphemeralTrack,
    addTrack,
    addTracks,
    addTrackToEnd: addToQueue,
    addTrackNext: addToQueueNext,
    removeTrack: (id: string) => void removeFromLibrary(id),
  };
}
