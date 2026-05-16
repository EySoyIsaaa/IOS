import { Switch } from "@/components/ui/switch";
import { KnobControl } from "@/components/KnobControl";
import type { EffectParamConfig, TranslateFn } from "@/components/home/types";

interface HomeEffectsViewProps {
  t: TranslateFn;
  reverbEnabled: boolean;
  concertHallEnabled: boolean;
  params: EffectParamConfig[];
  onToggleReverb: (enabled: boolean) => void;
  onToggleConcertHall: (enabled: boolean) => void;
}

export function HomeEffectsView({
  t,
  reverbEnabled,
  concertHallEnabled,
  params,
  onToggleReverb,
  onToggleConcertHall,
}: HomeEffectsViewProps) {
  const reverbParam = params.find((param) => param.key === "reverbAmount");
  const concertHallParam = params.find(
    (param) => param.key === "concertHallAmount",
  );

  return (
    <div className="flex-1 flex flex-col" data-testid="effects-view">
      <header className="flex items-center justify-between px-6 pt-12 pb-4 border-b border-zinc-900">
        <div>
          <h2 className="text-xl font-bold">{t("effects.title")}</h2>
          <p className="text-xs text-zinc-600 mt-0.5">
            {t("effects.subtitle")}
          </p>
        </div>
        <div className="flex items-center gap-2 text-[10px] uppercase tracking-[0.2em] text-zinc-500">
          <div
            className={`w-2 h-2 rounded-full transition-all ${
              reverbEnabled || concertHallEnabled
                ? "bg-white shadow-[0_0_8px_rgba(255,255,255,0.8)]"
                : "bg-zinc-700"
            }`}
          />
          {t("effects.live")}
        </div>
      </header>

      <div className="flex-1 flex flex-col justify-center px-4 py-8 gap-5">
        <section className="card-elevated rounded-2xl p-6 space-y-5">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h3 className="text-sm font-bold tracking-[0.14em] uppercase">
                {t("effects.reverb")}
              </h3>
              <p className="text-xs text-zinc-500 mt-1 leading-relaxed">
                {t("effects.reverbDescription")}
              </p>
            </div>
            <Switch
              checked={reverbEnabled}
              onCheckedChange={onToggleReverb}
            />
          </div>
          {reverbParam && (
            <div className="flex justify-center">
              <KnobControl {...reverbParam} disabled={!reverbEnabled} />
            </div>
          )}
        </section>

        <section className="card-elevated rounded-2xl p-6 space-y-5">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h3 className="text-sm font-bold tracking-[0.14em] uppercase">
                {t("effects.concertHall")}
              </h3>
              <p className="text-xs text-zinc-500 mt-1 leading-relaxed">
                {t("effects.concertHallDescription")}
              </p>
            </div>
            <Switch
              checked={concertHallEnabled}
              onCheckedChange={onToggleConcertHall}
            />
          </div>
          {concertHallParam && (
            <div className="flex justify-center">
              <KnobControl
                {...concertHallParam}
                disabled={!concertHallEnabled}
              />
            </div>
          )}
        </section>

        <p className="text-center text-xs text-zinc-600 px-8">
          {t("effects.description")}
        </p>
      </div>
    </div>
  );
}

export default HomeEffectsView;
