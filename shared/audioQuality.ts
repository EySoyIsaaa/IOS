export const HI_RES_MIN_BIT_DEPTH = 24;
export const HI_RES_MIN_SAMPLE_RATE = 48000;
export const HI_RES_UNKNOWN_DEPTH_SAMPLE_RATE = 88200;

const LOSSLESS_EXTENSIONS = new Set(['wav', 'wave', 'aif', 'aiff', 'flac', 'alac', 'caf']);
const LOSSY_EXTENSIONS = new Set(['mp3', 'aac', 'm4a', 'm4b', 'ogg', 'opus']);

const normalizeExtension = (fileExtension?: string | null): string | undefined => {
  if (typeof fileExtension !== 'string') return undefined;
  const clean = fileExtension.trim().toLowerCase().replace(/^\./, '');
  return clean || undefined;
};

export function isLosslessContainer(fileExtension?: string | null): boolean {
  const extension = normalizeExtension(fileExtension);
  return extension ? LOSSLESS_EXTENSIONS.has(extension) : false;
}

export function isLossyContainer(fileExtension?: string | null): boolean {
  const extension = normalizeExtension(fileExtension);
  return extension ? LOSSY_EXTENSIONS.has(extension) : false;
}

export function isHiResQuality(bitDepth?: number, sampleRate?: number, fileExtension?: string | null): boolean {
  if (typeof sampleRate !== "number" || !Number.isFinite(sampleRate) || sampleRate <= 0) {
    return false;
  }

  if (typeof bitDepth === "number" && Number.isFinite(bitDepth) && bitDepth > 0) {
    return bitDepth >= HI_RES_MIN_BIT_DEPTH && sampleRate >= HI_RES_MIN_SAMPLE_RATE;
  }

  return sampleRate >= HI_RES_UNKNOWN_DEPTH_SAMPLE_RATE && isLosslessContainer(fileExtension);
}

export type AudioQualityClass = 'hi-res' | 'cd' | 'lossless' | 'lossy' | 'standard' | 'unknown';

export function classifyAudioQuality(
  bitDepth?: number,
  sampleRate?: number,
  bitrate?: number,
  fileExtension?: string | null,
): AudioQualityClass {
  if (isHiResQuality(bitDepth, sampleRate, fileExtension)) return 'hi-res';

  const hasBitDepth = typeof bitDepth === 'number' && Number.isFinite(bitDepth) && bitDepth > 0;
  const hasSampleRate = typeof sampleRate === 'number' && Number.isFinite(sampleRate) && sampleRate > 0;

  if (hasBitDepth && hasSampleRate && bitDepth === 16 && sampleRate === 44100) return 'cd';
  if (isLossyContainer(fileExtension)) return 'lossy';
  if (isLosslessContainer(fileExtension) && (hasBitDepth || hasSampleRate)) return 'lossless';
  if (hasBitDepth || hasSampleRate || (typeof bitrate === 'number' && bitrate > 0)) return 'standard';
  return 'unknown';
}

export function qualityClassLabel(qualityClass: AudioQualityClass): string {
  switch (qualityClass) {
    case 'hi-res': return 'HI-RES';
    case 'cd': return 'CD QUALITY';
    case 'lossless': return 'LOSSLESS';
    case 'lossy': return 'LOSSY';
    case 'standard': return 'STANDARD';
    case 'unknown': return 'UNKNOWN';
  }
}

export function formatQualityLabel(bitDepth?: number, sampleRate?: number): string {
  const parts: string[] = [];

  if (typeof bitDepth === "number") {
    parts.push(`${bitDepth}-bit`);
  }

  if (typeof sampleRate === "number") {
    const sampleRateKHz = (sampleRate / 1000).toFixed(sampleRate % 1000 === 0 ? 0 : 1);
    parts.push(`${sampleRateKHz}kHz`);
  }

  return parts.join(" ");
}
