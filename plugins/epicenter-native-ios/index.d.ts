import type { PluginListenerHandle } from '@capacitor/core';

export interface EpicenterState {
  enabled: boolean;
  intensity: number;
  sweepFreq: number;
  width: number;
  balance: number;
  volume: number;
}

export interface EqState {
  enabled: boolean;
  bands: number[];
  frequencies: number[];
  headroomDb: number;
}

export interface FxState {
  reverbEnabled: boolean;
  reverbAmount: number;
  reverbWetDryMix?: number;
  concertHallEnabled: boolean;
  concertHallAmount: number;
  concertHallWetDryMix?: number;
  combinedMode?: string;
  outputVolume?: number;
}

export interface EpicenterNativeIosPlugin {
  setEpicenterEnabled(params: { enabled: boolean }): Promise<{ status: string; epicenter: EpicenterState }>;
  setEpicenterParams(params: Partial<Omit<EpicenterState, 'enabled'>> & { sweep?: number; output?: number }): Promise<{ status: string; epicenter: EpicenterState }>;
  setEqEnabled(params: { enabled: boolean }): Promise<EqState & { status: string }>;
  setEqBand(params: { index: number; gain: number }): Promise<EqState & { status: string }>;
  setEqBands(params: { gains: number[] }): Promise<EqState & { status: string }>;
  setEqPreset(params: { name?: string; gains: number[] }): Promise<EqState & { status: string; preset?: string | null }>;
  resetEq(): Promise<EqState & { status: string }>;
  setReverbEnabled(params: { enabled: boolean }): Promise<FxState & { status: string }>;
  setReverbAmount(params: { amount: number }): Promise<FxState & { status: string }>;
  setConcertHallEnabled(params: { enabled: boolean }): Promise<FxState & { status: string }>;
  setConcertHallAmount(params: { amount: number }): Promise<FxState & { status: string }>;
  getPlaybackState(): Promise<Record<string, unknown>>;
  addListener(eventName: string, listenerFunc: (event: Record<string, unknown>) => void): Promise<PluginListenerHandle>;
  removeAllListeners(): Promise<void>;
}
