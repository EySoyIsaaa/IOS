import { registerPlugin, type PluginListenerHandle } from "@capacitor/core";

export type IOSNativeAudioStatus =
  | "ok"
  | "not_found"
  | "not_implemented"
  | "error";

export interface IOSNativeTrack {
  id: string;
  stableId: string;
  title: string;
  artist?: string | null;
  album?: string | null;
  durationMs: number;
  fileName: string;
  fileExtension: string;
  codec?: string | null;
  qualityClass?: string | null;
  sourceUri: string;
  sourceUrl?: string | null;
  originalUrl?: string | null;
  playbackUrl?: string | null;
  optimizedUrl?: string | null;
  optimizedForPlayback?: boolean;
  optimizationStatus?: "pending" | "processing" | "ready" | "failed";
  optimizationError?: string | null;
  originalBitDepth?: number | null;
  originalSampleRate?: number | null;
  originalBitrate?: number | null;
  originalFormat?: string | null;
  bookmarkData?: string | null;
  localFilePath?: string | null;
  sourceType: "manual-ios";
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
  sort?: "title" | "artist" | "album" | "duration" | "addedAt" | "updatedAt";
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
  epicenter?: IOSNativeEpicenterState;
  eq?: IOSNativeEqState;
  fx?: IOSNativeFxState;
}

export interface IOSNativeEqState {
  enabled: boolean;
  bands: number[];
  frequencies: number[];
  headroomDb: number;
}

export interface IOSNativeFxState {
  reverbEnabled: boolean;
  reverbAmount: number;
  reverbWetDryMix?: number;
  concertHallEnabled: boolean;
  concertHallAmount: number;
  concertHallWetDryMix?: number;
  combinedMode?: string;
  outputVolume?: number;
}

export interface IOSNativeEpicenterState {
  enabled: boolean;
  intensity: number;
  sweepFreq: number;
  width: number;
  balance: number;
  volume: number;
}

export interface IOSNativeSetQueueResult {
  status: IOSNativeAudioStatus;
  queue: IOSNativePlaybackQueue;
}

export interface IOSNativePlaybackErrorEvent {
  status: "error";
  code: string;
  message: string;
  trackId?: string;
}

export interface IOSNativeCurrentTrackChangedEvent {
  status: IOSNativeAudioStatus;
  requestId?: string;
  index?: number;
  track: IOSNativeTrack;
}

export interface IOSNativeAudioRouteChangedEvent {
  reason: string;
}

export type IOSNativeProgressChangedEvent = IOSNativePlaybackState;
export type IOSNativePlaybackStateChangedEvent = IOSNativePlaybackState;

export interface EpicenterNativePlugin {
  importTracks(): Promise<IOSNativeImportTracksResult>;
  getLibraryPage(
    params?: IOSNativeLibraryPageParams,
  ): Promise<IOSNativeLibraryPageResult>;
  getTrack(params: { id: string }): Promise<IOSNativeTrackResult>;
  deleteTrack(params: { id: string }): Promise<IOSNativeDeleteTrackResult>;
  getPlaybackState(): Promise<IOSNativePlaybackState>;
  setQueue(params: {
    trackIds: string[];
    startIndex?: number;
  }): Promise<IOSNativeSetQueueResult>;
  play(params?: { trackId?: string }): Promise<IOSNativePlaybackState>;
  pause(): Promise<IOSNativePlaybackState>;
  seek(params: { seconds: number }): Promise<IOSNativePlaybackState>;
  stop(): Promise<IOSNativePlaybackState>;
  next(params?: { requestId?: string }): Promise<IOSNativePlaybackState>;
  previous(params?: { requestId?: string }): Promise<IOSNativePlaybackState>;
  setEpicenterEnabled(params: {
    enabled: boolean;
  }): Promise<Record<string, unknown>>;
  setEpicenterParams(
    params: Partial<Omit<IOSNativeEpicenterState, "enabled">> & {
      output?: number;
      sweep?: number;
    },
  ): Promise<Record<string, unknown>>;
  setEqEnabled(params: { enabled: boolean }): Promise<Record<string, unknown>>;
  setEqBand(params: {
    index: number;
    gain: number;
  }): Promise<Record<string, unknown>>;
  setEqBands(params: { gains: number[] }): Promise<Record<string, unknown>>;
  setEqPreset(params: {
    name?: string;
    gains: number[];
  }): Promise<Record<string, unknown>>;
  resetEq(): Promise<Record<string, unknown>>;
  setReverbEnabled(params: {
    enabled: boolean;
  }): Promise<Record<string, unknown>>;
  setReverbAmount(params: { amount: number }): Promise<Record<string, unknown>>;
  setConcertHallEnabled(params: {
    enabled: boolean;
  }): Promise<Record<string, unknown>>;
  setConcertHallAmount(params: {
    amount: number;
  }): Promise<Record<string, unknown>>;
  addListener(
    eventName: "playbackStateChanged",
    listenerFunc: (event: IOSNativePlaybackStateChangedEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: "currentTrackChanged",
    listenerFunc: (event: IOSNativeCurrentTrackChangedEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: "progressChanged",
    listenerFunc: (event: IOSNativeProgressChangedEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: "playbackError",
    listenerFunc: (event: IOSNativePlaybackErrorEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: "audioRouteChanged",
    listenerFunc: (event: IOSNativeAudioRouteChangedEvent) => void,
  ): Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;
}

export const EpicenterNative =
  registerPlugin<EpicenterNativePlugin>('EpicenterNative');
