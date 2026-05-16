import { Disc3, Library, Search, Settings, SlidersHorizontal } from "lucide-react";

type TabType = "player" | "library" | "search" | "eq" | "dsp" | "fx" | "settings";

type BottomNavigationProps = {
  activeTab: TabType;
  onTabChange: (tab: TabType) => void;
  onLibraryTab: () => void;
  eqEnabled: boolean;
  epicenterEnabled: boolean;
  spatialEffectsEnabled: boolean;
  t: (key: string) => string;
};

export function BottomNavigation({
  activeTab,
  onTabChange,
  onLibraryTab,
  eqEnabled,
  epicenterEnabled,
  spatialEffectsEnabled,
  t,
}: BottomNavigationProps) {
  const dspActive = ["dsp", "eq", "fx"].includes(activeTab);
  const dspOnline = eqEnabled || epicenterEnabled || spatialEffectsEnabled;
  const itemClass = (active: boolean) =>
    `relative flex min-w-0 flex-1 flex-col items-center gap-1 rounded-xl px-2 py-2 transition-colors ${
      active ? "text-[var(--ep-red)]" : "text-[var(--ep-text-muted)]"
    }`;

  const label = (key: string, fallback: string) => {
    const translated = t(key);
    return translated === key ? fallback : translated;
  };

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 border-t border-[var(--ep-border)] bg-[var(--ep-surface)] px-2 pt-2 shadow-[0_-10px_28px_rgba(0,0,0,0.55)] bottom-nav-safe">
      <div className="flex items-center justify-around bg-[linear-gradient(180deg,#121212,#060606)] p-1">
        <button onClick={() => onTabChange("player")} className={itemClass(activeTab === "player")}>
          {activeTab === "player" && <span className="absolute top-0 h-0.5 w-8 rounded-full bg-[var(--ep-red)] shadow-[0_0_12px_rgba(255,16,42,0.8)]" />}
          <Disc3 className="h-5 w-5" strokeWidth={1.7} />
          <span className="text-[10px] font-black uppercase tracking-[0.12em]">Inicio</span>
        </button>
        <button onClick={onLibraryTab} className={itemClass(activeTab === "library")}>
          {activeTab === "library" && <span className="absolute top-0 h-0.5 w-8 rounded-full bg-[var(--ep-red)] shadow-[0_0_12px_rgba(255,16,42,0.8)]" />}
          <Library className="h-5 w-5" strokeWidth={1.7} />
          <span className="text-[10px] font-black uppercase tracking-[0.12em]">{label("tabs.library", "Biblioteca")}</span>
        </button>
        <button onClick={() => onTabChange("search")} className={itemClass(activeTab === "search")}>
          {activeTab === "search" && <span className="absolute top-0 h-0.5 w-8 rounded-full bg-[var(--ep-red)] shadow-[0_0_12px_rgba(255,16,42,0.8)]" />}
          <Search className="h-5 w-5" strokeWidth={1.7} />
          <span className="text-[10px] font-black uppercase tracking-[0.12em]">{label("tabs.search", "Buscar")}</span>
        </button>
        <button onClick={() => onTabChange("dsp")} className={itemClass(dspActive)}>
          {dspActive && <span className="absolute top-0 h-0.5 w-8 rounded-full bg-[var(--ep-red)] shadow-[0_0_12px_rgba(255,16,42,0.8)]" />}
          {dspOnline && <span className="absolute right-3 top-2 h-1.5 w-1.5 rounded-full bg-[var(--ep-red)] shadow-[0_0_8px_rgba(255,16,42,0.85)]" />}
          <SlidersHorizontal className="h-5 w-5" strokeWidth={1.7} />
          <span className="text-[10px] font-black uppercase tracking-[0.12em]">DSP</span>
        </button>
        <button onClick={() => onTabChange("settings")} className={itemClass(activeTab === "settings")}>
          {activeTab === "settings" && <span className="absolute top-0 h-0.5 w-8 rounded-full bg-[var(--ep-red)] shadow-[0_0_12px_rgba(255,16,42,0.8)]" />}
          <Settings className="h-5 w-5" strokeWidth={1.7} />
          <span className="text-[10px] font-black uppercase tracking-[0.12em]">{label("tabs.settings", "Ajustes")}</span>
        </button>
      </div>
    </nav>
  );
}
