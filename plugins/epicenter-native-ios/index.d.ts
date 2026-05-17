import type { PluginListenerHandle } from '@capacitor/core';

export interface EpicenterState {
  enabled: boolean;
  intensity: number;
  sweepFreq: number;
  width: number;
  balance: number;
  volume: number;
}

export interface EpicenterNativeIosPlugin {
  setEpicenterEnabled(params: { enabled: boolean }): Promise<{ status: string; epicenter: EpicenterState }>;
  setEpicenterParams(params: Partial<Omit<EpicenterState, 'enabled'>> & { sweep?: number; output?: number }): Promise<{ status: string; epicenter: EpicenterState }>;
  getPlaybackState(): Promise<Record<string, unknown>>;
  addListener(eventName: string, listenerFunc: (event: Record<string, unknown>) => void): Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;
}
