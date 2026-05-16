import { useEffect, useRef } from "react";
import { KnobControl } from "@/components/KnobControl";
import { Switch } from "@/components/ui/switch";
import type { TranslateFn } from "@/components/home/types";

const SIGNAL_METER_BARS = [22, 34, 47, 61, 78, 86, 69, 58, 44, 31, 24, 18];

interface HomeFxViewProps {
  t: TranslateFn;
  reverbEnabled: boolean;
  reverbAmount: number;
  concertHallEnabled: boolean;
  concertHallAmount: number;
  onToggleReverb: (enabled: boolean) => void;
  onReverbAmountChange: (value: number) => void;
  onToggleConcertHall: (enabled: boolean) => void;
  onConcertHallAmountChange: (value: number) => void;
}

export function HomeFxView({
  t,
  reverbEnabled,
  reverbAmount,
  concertHallEnabled,
  concertHallAmount,
  onToggleReverb,
  onReverbAmountChange,
  onToggleConcertHall,
  onConcertHallAmountChange,
}: HomeFxViewProps) {
  const viewRef = useRef<HTMLDivElement | null>(null);
  const effectsEnabled = reverbEnabled || concertHallEnabled;

  useEffect(() => {
    viewRef.current?.scrollTo({ top: 0, left: 0 });
  }, []);
  return (
    <div ref={viewRef} className="flex-1 overflow-y-auto px-4 pb-32 pt-12" data-testid="fx-view">
      <header className="mb-5 flex items-start justify-between gap-4">
        <div>
          <p className="premium-title text-[10px] font-black text-[var(--ep-red)]">DSP Rack / Output</p>
          <h2 className="premium-title mt-1 text-2xl font-black text-white">{t("fx.title")}</h2>
          <p className="mt-1 text-xs text-[var(--ep-text-secondary)]">{t("fx.subtitle")}</p>
        </div>
        <div className="rounded-full border border-[var(--ep-border)] bg-[#0b0b0b] px-3 py-2 text-[10px] font-black uppercase tracking-[0.16em] text-[var(--ep-text-secondary)]">
          <span className={`mr-2 inline-block h-2 w-2 rounded-full ${effectsEnabled ? "bg-[var(--ep-red)] shadow-[0_0_8px_rgba(255,16,42,0.85)]" : "bg-zinc-700"}`} />
          {effectsEnabled ? t("fx.on") : t("fx.off")}
        </div>
      </header>

      <section className="premium-card rounded-3xl p-5">
        <div className="mb-5 flex items-start justify-between gap-4">
          <div>
            <h3 className="premium-title text-sm font-black text-white">Bass Boost / {t("fx.reverb")}</h3>
            <p className="mt-1 text-xs leading-relaxed text-[var(--ep-text-muted)]">{t("fx.reverbDescription")}</p>
          </div>
          <Switch checked={reverbEnabled} onCheckedChange={onToggleReverb} />
        </div>
        <div className="flex items-center justify-between gap-4">
          <div className="space-y-2 text-[10px] font-bold uppercase tracking-[0.14em] text-[var(--ep-text-muted)]">
            <p>{t("fx.reverbSpecOne")}</p>
            <p>{t("fx.reverbSpecTwo")}</p>
            <p>{t("fx.reverbSpecThree")}</p>
          </div>
          <KnobControl label={t("fx.amount")} value={reverbAmount} min={0} max={100} step={1} unit="%" onChange={onReverbAmountChange} disabled={!reverbEnabled} featured />
        </div>
      </section>

      <section className="premium-card mt-4 rounded-3xl p-5">
        <div className="mb-5 flex items-start justify-between gap-4">
          <div>
            <h3 className="premium-title text-sm font-black text-white">Enhancer / Stereo Expander</h3>
            <p className="mt-1 text-xs leading-relaxed text-[var(--ep-text-muted)]">{t("fx.concertHallDescription")}</p>
          </div>
          <Switch checked={concertHallEnabled} onCheckedChange={onToggleConcertHall} />
        </div>
        <div className="flex items-center justify-between gap-4">
          <div className="space-y-2 text-[10px] font-bold uppercase tracking-[0.14em] text-[var(--ep-text-muted)]">
            <p>{t("fx.concertSpecOne")}</p>
            <p>{t("fx.concertSpecTwo")}</p>
            <p>{t("fx.concertSpecThree")}</p>
          </div>
          <KnobControl label={t("fx.amount")} value={concertHallAmount} min={0} max={100} step={1} unit="%" onChange={onConcertHallAmountChange} disabled={!concertHallEnabled} featured />
        </div>
      </section>

      <section className="mt-4 rounded-3xl border border-[var(--ep-border)] bg-[#080808] p-5">
        <p className="premium-title mb-4 text-sm font-black text-white">Salida / Diagnóstico de señal</p>
        <div className="grid grid-cols-3 gap-3 text-center">
          {["Limiter", "Phase", "Crossover"].map((label) => (
            <div key={label} className="rounded-2xl border border-[var(--ep-border)] bg-[#111] p-3">
              <p className="text-[10px] font-black uppercase tracking-[0.14em] text-[var(--ep-text-muted)]">{label}</p>
              <p className="mt-1 text-xs font-bold text-white">Ready</p>
            </div>
          ))}
        </div>
        <div className="mt-5 space-y-2">
          <div className="flex justify-between text-[10px] font-black uppercase tracking-[0.14em] text-[var(--ep-text-muted)]"><span>Signal</span><span>-3 dB</span></div>
          <div className="flex h-10 items-end gap-1 rounded-xl border border-[var(--ep-border)] bg-black p-2">
            {SIGNAL_METER_BARS.map((height, index) => <span key={index} className="signal-meter-bar flex-1 rounded-sm" style={{ height: `${height}%`, opacity: 0.28 + index / 18 }} />)}
          </div>
        </div>
      </section>

      <p className="mt-5 px-6 text-center text-xs leading-relaxed text-[var(--ep-text-muted)]">{t("fx.description")}</p>
    </div>
  );
}

export default HomeFxView;
