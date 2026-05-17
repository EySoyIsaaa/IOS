import { Capacitor } from "@capacitor/core";
import { isHiResQuality } from "@shared/audioQuality";
import type { IOSNativeTrack } from "@/native/iosNativeAudio";

export interface IOSAppTrack {
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
  album?: string;
  duration: number;
  coverUrl?: string;
  bitDepth?: number;
  sampleRate?: number;
  bitrate?: number;
  isHiRes?: boolean;
  qualityClass?: string;
  sourceUri?: string;
  sourceUrl?: string;
  originalUrl?: string;
  playbackUrl?: string;
  optimizedUrl?: string;
  optimizedForPlayback?: boolean;
  optimizationStatus?: "pending" | "processing" | "ready" | "failed";
  optimizationError?: string;
  originalBitDepth?: number;
  originalSampleRate?: number;
  originalBitrate?: number;
  originalFormat?: string;
  sourceType?: "manual-ios";
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

const COPIED_FILE_UUID_SUFFIX =
  /-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const cleanText = (value?: string | null): string | undefined => {
  if (typeof value !== "string") return undefined;
  const trimmed = value.trim();
  if (
    !trimmed ||
    trimmed.toLowerCase() === "null" ||
    trimmed.toLowerCase() === "undefined"
  )
    return undefined;
  return trimmed;
};

const titleFromFileName = (fileName?: string | null): string | undefined => {
  const cleanFileName = cleanText(fileName);
  if (!cleanFileName) return undefined;
  const withoutExtension = cleanFileName.replace(/\.[^.]+$/, "");
  return (
    withoutExtension.replace(COPIED_FILE_UUID_SUFFIX, "").trim() || undefined
  );
};

const normalizeLocalFileUrl = (path?: string | null): string | undefined => {
  const cleanPath = cleanText(path);
  if (!cleanPath) return undefined;
  if (/^(capacitor|https?|blob|data):/i.test(cleanPath)) return cleanPath;
  return Capacitor.convertFileSrc(cleanPath);
};

const numberOrUndefined = (value?: number | null): number | undefined =>
  typeof value === "number" && Number.isFinite(value) && value > 0
    ? value
    : undefined;

export const nativeTrackToAppTrack = (
  track: Partial<IOSNativeTrack> | null | undefined,
): IOSAppTrack | null => {
  if (!track || typeof track !== "object") return null;
  const id = cleanText(track.id);
  if (!id) return null;
  const fileName = cleanText(track.fileName);
  const title =
    cleanText(track.title)?.replace(COPIED_FILE_UUID_SUFFIX, "").trim() ||
    titleFromFileName(fileName) ||
    "Untitled";
  const artist =
    cleanText(track.artist) || cleanText(track.album) || "Unknown Artist";
  const sampleRate = numberOrUndefined(
    track.originalSampleRate ?? track.sampleRate,
  );
  const bitDepth = numberOrUndefined(track.originalBitDepth ?? track.bitDepth);
  const bitrate = numberOrUndefined(track.originalBitrate ?? track.bitrate);
  const codec = cleanText(track.codec) || cleanText(track.fileExtension);
  const albumArtUri = cleanText(track.albumArtUri);
  const fileExtension = cleanText(track.fileExtension)?.toLowerCase();
  const originalUrl = cleanText(
    track.originalUrl ??
      track.sourceUrl ??
      track.sourceUri ??
      track.localFilePath,
  );
  const playbackUrl = cleanText(
    track.playbackUrl ?? track.localFilePath ?? originalUrl ?? track.sourceUri,
  );
  const optimizationStatus = track.optimizationStatus ?? "ready";

  return {
    id,
    sourceTrackId: cleanText(track.stableId),
    fileName,
    fileType: track.fileExtension ? `audio/${track.fileExtension}` : undefined,
    codec,
    qualityClass: cleanText(track.qualityClass),
    fileSize: numberOrUndefined(track.sizeBytes),
    title,
    artist,
    album: cleanText(track.album),
    duration: Math.max(0, Math.round((track.durationMs || 0) / 1000)),
    coverUrl: normalizeLocalFileUrl(albumArtUri),
    bitDepth,
    sampleRate,
    bitrate,
    isHiRes: isHiResQuality(bitDepth, sampleRate, codec, track.fileExtension),
    sourceUri: cleanText(track.sourceUri),
    sourceUrl: originalUrl,
    originalUrl,
    playbackUrl,
    optimizedUrl: cleanText(track.optimizedUrl),
    optimizedForPlayback: !!track.optimizedForPlayback,
    optimizationStatus,
    optimizationError: cleanText(track.optimizationError),
    originalBitDepth: bitDepth,
    originalSampleRate: sampleRate,
    originalBitrate: bitrate,
    originalFormat: cleanText(track.originalFormat ?? track.fileExtension),
    sourceType: "manual-ios",
    albumArtUri: albumArtUri ?? undefined,
    unavailable: !track.isAvailable,
  };
};
