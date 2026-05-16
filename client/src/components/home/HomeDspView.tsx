import { useEffect, useRef } from "react";
import { SlidersHorizontal, Waves } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Switch } from "@/components/ui/switch";
import { KnobControl } from "@/components/KnobControl";
import type { DspParamConfig, TranslateFn } from "@/components/home/types";

interface HomeDspViewProps {
  t: TranslateFn;
  epicenterEnabled: boolean;
  params: DspParamConfig[];
  onOpenAutoModal: () => void;
  onToggleEpicenter: () => void;
  onOpenEq?: () => void;
  onOpenFx?: () => void;
}


export function HomeDspView({
  t,
  epicenterEnabled,
  params,
  onOpenAutoModal,
  onToggleEpicenter,
  onOpenEq,
  onOpenFx,
}: HomeDspViewProps) {
  const viewRef = useRef<HTMLDivElement | null>(null);
  const mainParam = params.find((param) => param.key === "intensity") ?? params[0];

  useEffect(() => {
    viewRef.current?.scrollTo({ top: 0, left: 0 });
  }, []);
  const secondaryParams = params.filter((param) => param.key !== mainParam.key);

  return (
    <div ref={viewRef} className="flex-1 overflow-y-auto px-4 pb-32 pt-12" data-testid="dsp-view">
      <header className="mb-5 flex items-start justify-between gap-4">
        <div>
          <p className="premium-title text-[10px] font-black text-[var(--ep-red)]">EpicenterDSP 7.0</p>
          <h2 className="premium-title mt-1 text-2xl font-black text-white">{t("dsp.title")}</h2>
          <p className="mt-1 text-xs text-[var(--ep-text-secondary)]">{t("dsp.subtitle")}</p>
        </div>
        <div className="flex flex-col items-end gap-2">
          <Button onClick={onOpenAutoModal} className="h-auto rounded-full border border-[rgba(255,16,42,0.45)] bg-[#101010] px-3 py-1.5 text-[10px] font-black uppercase tracking-[0.14em] text-white hover:bg-[#181818]">
            {t("dsp.autoButton")}
          </Button>
          <div className="flex items-center gap-2 rounded-full border border-[var(--ep-border)] bg-[#0b0b0b] px-3 py-1.5">
            <span className={`h-2 w-2 rounded-full ${epicenterEnabled ? "bg-[var(--ep-red)] shadow-[0_0_10px_rgba(255,16,42,0.9)]" : "bg-zinc-700"}`} />
            <span className="text-[9px] font-black uppercase tracking-[0.16em] text-[var(--ep-text-secondary)]">{epicenterEnabled ? "Active" : "Bypass"}</span>
            <Switch checked={epicenterEnabled} onCheckedChange={onToggleEpicenter} />
          </div>
        </div>
      </header>

      <section className="premium-card rounded-3xl p-5 text-center">
        <div className="mx-auto mb-3 inline-flex items-center gap-2 rounded-full border border-[rgba(255,16,42,0.35)] bg-black px-3 py-1 text-[10px] font-black uppercase tracking-[0.18em] text-[var(--ep-text-secondary)]">
          <span className="h-1.5 w-1.5 rounded-full bg-[var(--ep-red)]" />
          Epicenter Engine {epicenterEnabled ? "Active" : "Standby"}
        </div>
        <KnobControl {...mainParam} label="INTENSIDAD" size={172} featured disabled={mainParam.disabled} />
        <div className="mt-4 h-9 overflow-hidden rounded-xl border border-[var(--ep-border)] bg-black/80 px-4 py-2">
          <div className="flex h-full items-end justify-center gap-1">
            {Array.from({ length: 32 }).map((_, index) => (
              <span
                key={index}
                className="w-1 rounded-t bg-[var(--ep-red)] shadow-[0_0_8px_rgba(255,16,42,0.35)]"
                style={{ height: `${18 + ((index * 7) % 19)}px`, opacity: epicenterEnabled ? 0.28 + (index % 5) * 0.12 : 0.12 }}
              />
            ))}
          </div>
        </div>
      </section>

      <section className="mt-4 grid grid-cols-2 gap-3">
        {secondaryParams.map((param) => (
          <div key={param.key} className={`premium-card rounded-2xl p-3 ${param.key === "volume" ? "red-glow-subtle" : ""}`}>
            <KnobControl {...param} size={92} featured={false} />
          </div>
        ))}
      </section>

      <section className="mt-4 grid grid-cols-2 gap-3">
        <button onClick={onOpenEq} className="premium-card min-h-28 rounded-3xl p-5 text-left">
          <SlidersHorizontal className="mb-3 h-5 w-5 text-[var(--ep-red)]" />
          <p className="premium-title text-lg font-black text-white">ECUALIZADOR</p>
          <p className="mt-1 text-xs text-[var(--ep-text-muted)]">Curva DSP, faders y Q factor</p>
        </button>
        <button onClick={onOpenFx} className="premium-card min-h-28 rounded-3xl p-5 text-left">
          <Waves className="mb-3 h-5 w-5 text-[var(--ep-red)]" />
          <p className="premium-title text-lg font-black text-white">EFECTOS</p>
          <p className="mt-1 text-xs text-[var(--ep-text-muted)]">Boost, enhancer y salida</p>
        </button>
      </section>

      <p className="mt-5 px-5 text-center text-xs leading-relaxed text-[var(--ep-text-muted)]">{t("dsp.description")}</p>
    </div>
  );
}

export default HomeDspView;
