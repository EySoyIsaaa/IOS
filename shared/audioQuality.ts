export const HI_RES_MIN_BIT_DEPTH = 24;
export const HI_RES_MIN_SAMPLE_RATE = 48000;
export const HI_RES_FALLBACK_SAMPLE_RATE = 88200;
export const CD_QUALITY_BIT_DEPTH = 16;
export const CD_QUALITY_SAMPLE_RATE = 44100;

const LOSSLESS_EXTENSIONS = new Set(['wav', 'wave', 'aif', 'aiff', 'aifc', 'flac', 'alac', 'caf']);
const LOSSLESS_CODECS = new Set(['lpcm', 'alac', 'flac']);
const LOSSY_EXTENSIONS = new Set(['mp3', 'aac', 'm4a', 'mp4', 'm4b', 'ogg', 'opus']);
const LOSSY_CODECS = new Set(['mp3', 'aac', 'mp4a', 'opus', 'vorbis']);

const normalizeToken = (value?: string | null): string | undefined => {
  if (typeof value !== 'string') return undefined;
  const normalized = value.trim().toLowerCase().replace(/^\./, '');
  return normalized || undefined;
};

export function isLosslessAudioFormat(codecOrExtension?: string | null, fileExtension?: string | null): boolean {
  const tokens = [normalizeToken(codecOrExtension), normalizeToken(fileExtension)].filter(Boolean) as string[];
  return tokens.some((token) => LOSSLESS_CODECS.has(token) || LOSSLESS_EXTENSIONS.has(token));
}

export function isLossyAudioFormat(codecOrExtension?: string | null, fileExtension?: string | null): boolean {
  const codec = normalizeToken(codecOrExtension);
  if (codec && LOSSLESS_CODECS.has(codec)) return false;
  if (codec && LOSSY_CODECS.has(codec)) return true;

  const extension = normalizeToken(fileExtension);
  return !!extension && LOSSY_EXTENSIONS.has(extension);
}

export function isHiResQuality(
  bitDepth?: number,
  sampleRate?: number,
  codecOrExtension?: string | null,
  fileExtension?: string | null,
): boolean {
  if (typeof sampleRate !== 'number' || !Number.isFinite(sampleRate) || sampleRate <= 0) {
    return false;
  }

  if (typeof bitDepth === 'number' && Number.isFinite(bitDepth) && bitDepth > 0) {
    return bitDepth >= HI_RES_MIN_BIT_DEPTH && sampleRate >= HI_RES_MIN_SAMPLE_RATE;
  }

  if (sampleRate < HI_RES_FALLBACK_SAMPLE_RATE) {
    return false;
  }

  const codec = normalizeToken(codecOrExtension);
  const hasLosslessCodec = !!codec && LOSSLESS_CODECS.has(codec);
  const hasLossyCodec = !!codec && LOSSY_CODECS.has(codec);
  if (hasLossyCodec) return false;
  if (hasLosslessCodec) return true;

  return isLosslessAudioFormat(undefined, fileExtension) && !isLossyAudioFormat(undefined, fileExtension);
}

export function isCdQuality(bitDepth?: number, sampleRate?: number): boolean {
  return bitDepth === CD_QUALITY_BIT_DEPTH && sampleRate === CD_QUALITY_SAMPLE_RATE;
}

export function qualityTier(
  bitDepth?: number,
  sampleRate?: number,
  bitrate?: number,
  codecOrExtension?: string | null,
  fileExtension?: string | null,
): 'hi-res' | 'cd' | 'lossy' | 'standard' | 'unknown' {
  if (isHiResQuality(bitDepth, sampleRate, codecOrExtension, fileExtension)) return 'hi-res';
  if (isCdQuality(bitDepth, sampleRate)) return 'cd';
  if (isLossyAudioFormat(codecOrExtension, fileExtension) || (typeof bitrate === 'number' && bitrate > 0 && !bitDepth)) return 'lossy';
  if (bitDepth || sampleRate || bitrate) return 'standard';
  return 'unknown';
}

export function formatQualityLabel(bitDepth?: number, sampleRate?: number): string {
  const parts: string[] = [];

  if (typeof bitDepth === 'number') {
    parts.push(`${bitDepth}-bit`);
  }

  if (typeof sampleRate === 'number') {
    const sampleRateKHz = (sampleRate / 1000).toFixed(sampleRate % 1000 === 0 ? 0 : 1);
    parts.push(`${sampleRateKHz}kHz`);
  }

  return parts.join(' ');
}
