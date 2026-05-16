import { useEffect, useRef } from "react";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { EQVisualizer } from "@/components/EQVisualizer";
import { EQ_GAIN_MAX, EQ_GAIN_MIN, type EqualizerBand } from "@/hooks/useIntegratedAudioProcessor";
import type { TranslateFn } from "@/components/home/types";

interface HomeEqViewProps {
  t: TranslateFn;
  eqEnabled: boolean;
  eqBands: EqualizerBand[];
  onToggleEq: (enabled: boolean) => void;
  onOpenAutoModal: () => void;
  onSetEqBandGain: (index: number, gain: number) => void;
  onResetEq: () => void;
}

export function HomeEqView({ t, eqEnabled, eqBands, onToggleEq, onOpenAutoModal, onSetEqBandGain, onResetEq }: HomeEqViewProps) {
  const viewRef = useRef<HTMLDivElement | null>(null);

  useEffect(() => {
    viewRef.current?.scrollTo({ top: 0, left: 0 });
  }, []);

  return (
    <div ref={viewRef} className="flex-1 overflow-y-auto px-4 pb-32 pt-12" data-testid="eq-view">
      <header className="mb-4 flex items-start justify-between gap-3">
        <div>
          <p className="premium-title text-[10px] font-black text-[var(--ep-red)]">DSP Equalizer</p>
          <h2 className="premium-title mt-1 text-2xl font-black text-white">{t("eq.title")}</h2>
        </div>
        <div className="flex items-center gap-2 rounded-full border border-[var(--ep-border)] bg-[#0b0b0b] px-3 py-1.5">
          <span className="text-[10px] font-black uppercase tracking-[0.14em] text-[var(--ep-text-secondary)]">{eqEnabled ? t("eq.on") : t("eq.off")}</span>
          <Switch checked={eqEnabled} onCheckedChange={onToggleEq} />
        </div>
      </header>
      <div className="mb-4 rounded-2xl border border-[rgba(255,16,42,0.35)] bg-[#0b0b0b] p-3">
        <p className="premium-title text-xs font-black text-white">{t("eq.autoBannerTitle")}</p>
        <p className="mt-1 text-[11px] leading-relaxed text-[var(--ep-text-secondary)]">{t("eq.autoBannerDescription")}</p>
      </div>
      <EQVisualizer bands={eqBands} enabled={eqEnabled} onBandChange={onSetEqBandGain} minGain={EQ_GAIN_MIN} maxGain={EQ_GAIN_MAX} horizontalControlLabel={t("eq.horizontalSlider")} />
      <div className="mt-4 grid grid-cols-2 gap-3">
        <Button onClick={onOpenAutoModal} className="rounded-full border border-[rgba(255,16,42,0.5)] bg-[#111] text-white hover:bg-[#181818]">{t("eq.autoButton")}</Button>
        <Button variant="outline" onClick={onResetEq} className="rounded-full border-[var(--ep-border)] bg-black text-[var(--ep-text-secondary)] hover:bg-[#111] hover:text-white">{t("eq.reset")}</Button>
      </div>
    </div>
  );
}

export default HomeEqView;
