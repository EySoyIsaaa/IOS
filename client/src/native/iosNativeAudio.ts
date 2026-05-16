import { registerPlugin } from '@capacitor/core';

export type IOSNativeAudioStatus = 'ok' | 'not_found' | 'not_implemented' | 'error';

export interface IOSNativeTrack {
  id: string;
  stableId: string;
  title: string;
  artist?: string | null;
  album?: string | null;
  durationMs: number;
  fileName: string;
  fileExtension: string;
  sourceUri: string;
  bookmarkData?: string | null;
  localFilePath?: string | null;
  sourceType: 'manual-ios';
  addedAt: string;
  updatedAt: string;
  sizeBytes: number;
  sampleRate?: number | null;
  bitDepth?: number | null;
  bitrate?: number | null;
  channelCount?: number | null;
  albumArtUri?: string | null;
  isAvailable: boolean;
  playCount: number;
  lastPlayedAt?: string | null;
}

export interface IOSNativeImportTracksResult {
  status: IOSNativeAudioStatus;
  tracks: IOSNativeTrack[];
}

export interface IOSNativeLibraryPageParams {
  offset?: number;
  limit?: number;
  search?: string;
  sort?: 'title' | 'artist' | 'album' | 'duration' | 'addedAt' | 'updatedAt';
}

export interface IOSNativeLibraryPageResult {
  status: IOSNativeAudioStatus;
  tracks: IOSNativeTrack[];
  offset: number;
  limit: number;
  total: number;
}

export interface IOSNativeTrackResult {
  status: IOSNativeAudioStatus;
  track: IOSNativeTrack | null;
}

export interface IOSNativeDeleteTrackResult {
  status: IOSNativeAudioStatus;
  deleted: boolean;
  track?: IOSNativeTrack;
}

export interface IOSNativePlaybackQueue {
  trackIds: string[];
  currentIndex: number;
  currentTrackId?: string | null;
}

export interface IOSNativePlaybackState {
  status: IOSNativeAudioStatus;
  isPlaying: boolean;
  currentTime: number;
  duration: number;
  durationMs?: number;
  currentTrackId?: string | null;
  stableId?: string | null;
  currentTrack?: IOSNativeTrack | null;
  queue?: IOSNativePlaybackQueue;
  code?: string;
  message?: string;
}

export interface IOSNativeSetQueueResult {
  status: IOSNativeAudioStatus;
  queue: IOSNativePlaybackQueue;
}

export interface EpicenterNativePlugin {
  importTracks(): Promise<IOSNativeImportTracksResult>;
  getLibraryPage(params?: IOSNativeLibraryPageParams): Promise<IOSNativeLibraryPageResult>;
  getTrack(params: { id: string }): Promise<IOSNativeTrackResult>;
  deleteTrack(params: { id: string }): Promise<IOSNativeDeleteTrackResult>;
  getPlaybackState(): Promise<IOSNativePlaybackState>;
  setQueue(params: { trackIds: string[]; startIndex?: number }): Promise<IOSNativeSetQueueResult>;
  play(params?: { trackId?: string }): Promise<IOSNativePlaybackState>;
  pause(): Promise<IOSNativePlaybackState>;
  seek(params: { seconds: number }): Promise<IOSNativePlaybackState>;
  stop(): Promise<IOSNativePlaybackState>;
  next(): Promise<IOSNativePlaybackState>;
  previous(): Promise<IOSNativePlaybackState>;
  setEpicenterEnabled(params: { enabled: boolean }): Promise<Record<string, unknown>>;
  setEqBands(params: { gains: number[] }): Promise<Record<string, unknown>>;
  setReverbEnabled(params: { enabled: boolean }): Promise<Record<string, unknown>>;
}

export const EpicenterNative = registerPlugin<EpicenterNativePlugin>('EpicenterNative');
