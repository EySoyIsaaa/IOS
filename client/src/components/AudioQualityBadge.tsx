/**
 * EpicenterDSP 7.0 - hardware-style audio quality badges.
 */

import { classifyAudioQuality, formatQualityLabel, isHiResQuality, qualityClassLabel } from "@shared/audioQuality";

interface AudioQualityBadgeProps {
  bitDepth?: number;
  sampleRate?: number;
  bitrate?: number;
  isHiRes?: boolean;
  fileExtension?: string;
  compact?: boolean;
  hiResLogoUrl?: string;
}

export function AudioQualityBadge({
  bitDepth,
  sampleRate,
  bitrate,
  isHiRes,
  fileExtension,
  compact = false,
  hiResLogoUrl,
}: AudioQualityBadgeProps) {
  const detectedHiRes = isHiResQuality(bitDepth, sampleRate, fileExtension);
  const isHighRes = typeof isHiRes === "boolean" ? isHiRes : detectedHiRes;
  const qualityClass = isHighRes ? 'hi-res' : classifyAudioQuality(bitDepth, sampleRate, bitrate, fileExtension);
  const parts = [formatQualityLabel(bitDepth, sampleRate)].filter(Boolean);

  if (typeof bitrate === "number" && bitrate > 0) {
    parts.push(`${Math.round(bitrate / 1000)}kbps`);
  }

  if (!parts.length) return null;

  if (compact) {
    return (
      <span
        className={`inline-flex items-center rounded border px-1.5 py-0.5 text-[8px] font-black tracking-[0.14em] uppercase ${
          isHighRes
            ? "border-[rgba(255,16,42,0.55)] text-[var(--ep-red)]"
            : "border-[var(--ep-border)] text-[var(--ep-text-muted)]"
        }`}
        data-testid="quality-badge-compact"
      >
        {`${qualityClassLabel(qualityClass)}${parts.length ? ` • ${parts.join(" • ").replace("-bit ", "b/").replace("kHz", "k")}` : ""}`}
      </span>
    );
  }

  const chips = [
    bitDepth ? `${bitDepth} BIT` : null,
    sampleRate ? `${Math.round(sampleRate / 100) / 10} kHz` : null,
    bitrate ? `${Math.round(bitrate / 1000)} kbps` : null,
  ].filter(Boolean);

  return (
    <div className="flex flex-wrap justify-center gap-2" data-testid="quality-badge">
      {isHighRes && hiResLogoUrl ? (
        <span className="quality-chip inline-flex items-center rounded-md px-2.5 py-1">
          <img src={hiResLogoUrl} alt="Hi-Res Audio" className="h-4 w-auto object-contain" />
        </span>
      ) : (
        <span className="quality-chip rounded-md px-2.5 py-1 text-[9px] font-black uppercase tracking-[0.18em]">
          {qualityClassLabel(qualityClass)}
        </span>
      )}
      {chips.map((chip) => (
        <span
          key={chip}
          className="quality-chip rounded-md px-2.5 py-1 text-[9px] font-black uppercase tracking-[0.18em]"
        >
          {chip}
        </span>
      ))}
    </div>
  );
}

export default AudioQualityBadge;
