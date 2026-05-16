import { useMemo, useRef, useState } from "react";
import type { EqualizerBand } from "@/hooks/useIntegratedAudioProcessor";

interface EQVisualizerProps {
  bands: EqualizerBand[];
  enabled: boolean;
  onBandChange: (index: number, gain: number) => void;
  minGain?: number;
  maxGain?: number;
  horizontalControlLabel?: string;
}

export function EQVisualizer({
  bands,
  enabled,
  onBandChange,
  minGain = -8,
  maxGain = 8,
  horizontalControlLabel,
}: EQVisualizerProps) {
  const railRef = useRef<HTMLDivElement | null>(null);
  const [scrollPercent, setScrollPercent] = useState(0);
  const labels = useMemo(() => bands.map((band) => band.label.replace(" Hz", "").replace(" kHz", "k")), [bands]);
  const range = Math.max(1, maxGain - minGain);

  const syncPercent = () => {
    const el = railRef.current;
    if (!el) return;
    setScrollPercent((el.scrollLeft / Math.max(1, el.scrollWidth - el.clientWidth)) * 100);
  };

  const handleHorizontalSlider = (value: number) => {
    const el = railRef.current;
    if (!el) return;
    el.scrollLeft = (value / 100) * Math.max(1, el.scrollWidth - el.clientWidth);
    setScrollPercent(value);
  };

  const curvePoints = bands
    .map((band, index) => {
      const x = 8 + (index / Math.max(1, bands.length - 1)) * 84;
      const y = 50 - ((band.gain / Math.max(Math.abs(minGain), Math.abs(maxGain))) * 34);
      return `${x},${Math.max(12, Math.min(88, y))}`;
    })
    .join(" ");

  return (
    <div className="flex h-full flex-col gap-4">
      <div className="technical-grid rounded-2xl border border-[var(--ep-border)] bg-black p-3">
        <div className="mb-2 flex items-center justify-between text-[10px] font-black uppercase tracking-[0.16em] text-[var(--ep-text-muted)]">
          <span>Response</span>
          <span>{enabled ? "Live" : "Bypass"}</span>
        </div>
        <svg viewBox="0 0 100 100" className="h-28 w-full overflow-visible" preserveAspectRatio="none" aria-hidden="true">
          <polyline points={curvePoints} fill="none" stroke={enabled ? "#ff102a" : "#52525b"} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" />
          {bands.map((band, index) => {
            const x = 8 + (index / Math.max(1, bands.length - 1)) * 84;
            const y = 50 - ((band.gain / Math.max(Math.abs(minGain), Math.abs(maxGain))) * 34);
            return <circle key={index} cx={x} cy={Math.max(12, Math.min(88, y))} r="1.8" fill="#181818" stroke={enabled ? "#ff102a" : "#52525b"} strokeWidth="1.2" />;
          })}
        </svg>
      </div>

      <div className="flex justify-between px-2 text-[10px] font-mono text-[var(--ep-text-muted)]">
        <span>+{maxGain} dB</span>
        <span>0</span>
        <span>{minGain} dB</span>
      </div>

      <div ref={railRef} onScroll={syncPercent} className="overflow-x-auto overflow-y-hidden rounded-2xl border border-[var(--ep-border)] bg-[#070707] px-3 py-3" style={{ touchAction: "pan-x" }}>
        <div className="flex min-h-[330px] min-w-max items-end gap-4 pb-2">
          {bands.map((band, index) => {
            const normalized = ((band.gain - minGain) / range) * 100;
            return (
              <div key={index} className="flex w-12 flex-none flex-col items-center">
                <div className="relative h-[260px] w-9 overflow-hidden rounded-xl border border-[#343434] bg-[linear-gradient(180deg,#161616,#090909)] shadow-[inset_0_1px_0_rgba(255,255,255,0.05)]">
                  <div className="absolute left-1/2 top-0 h-full w-px -translate-x-1/2 bg-[#2f2f2f]" />
                  <div className="absolute inset-x-1 bottom-1/2 h-px bg-[#444]" />
                  <div className="absolute inset-x-2 bottom-0 rounded-t bg-[var(--ep-red)] shadow-[0_0_12px_rgba(255,16,42,0.35)] transition-all duration-150" style={{ height: enabled ? `${normalized}%` : "50%", opacity: enabled ? 0.9 : 0.22 }} />
                  <div className="absolute left-1/2 h-3 w-8 -translate-x-1/2 rounded-sm border border-[#555] bg-[linear-gradient(180deg,#5b5b5b,#151515)] shadow-[0_4px_10px_rgba(0,0,0,0.45)] transition-all duration-150" style={{ bottom: `calc(${normalized}% - 6px)` }} />
                  <input
                    type="range"
                    min={minGain}
                    max={maxGain}
                    step={0.5}
                    value={band.gain}
                    onChange={(event) => onBandChange(index, parseFloat(event.target.value))}
                    disabled={!enabled}
                    className="absolute inset-0 z-10 h-full w-full cursor-ns-resize opacity-0 disabled:cursor-not-allowed"
                    style={{ writingMode: "vertical-lr", direction: "rtl", touchAction: "none" }}
                    data-testid={`eq-slider-${index}`}
                  />
                </div>
                <span className={`mt-2 text-[10px] font-black ${enabled ? "text-[var(--ep-text-secondary)]" : "text-zinc-700"}`}>{labels[index]}</span>
                <span className={`dsp-numeric text-[10px] tabular-nums ${enabled ? "text-[var(--ep-red)]" : "text-zinc-700"}`}>{band.gain > 0 ? "+" : ""}{band.gain.toFixed(1)}</span>
              </div>
            );
          })}
        </div>
      </div>

      <div className="px-1">
        {horizontalControlLabel && <p className="mb-1 text-[11px] text-[var(--ep-text-muted)]">{horizontalControlLabel}</p>}
        <input type="range" min={0} max={100} step={1} value={scrollPercent} onChange={(event) => handleHorizontalSlider(parseFloat(event.target.value))} className="progress-slider h-2 w-full cursor-ew-resize appearance-none rounded-full" aria-label={horizontalControlLabel || "Horizontal EQ navigation"} />
      </div>
    </div>
  );
}

export default EQVisualizer;
